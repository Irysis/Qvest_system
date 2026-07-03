"""
PG2 Phase E: FULL 327-factor book_dIR sweep (empirical sweep-max, not Gumbel approx).
Decisive multiple-testing check: run EVERY DB factor as a core-add at w in {0.5,1.0},
rank by book_dIR. If my 'survivors' are just the argmax of a noisy sweep whose top values
are inflated by chance, the whole top tail will be defense/momentum factors clustered near
the same value -> lever is a sweep artifact. Also seed-robustness of the ranking.
"""
import pandas as pd, numpy as np, json, os, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"
OUT=ROOT+"/stage_artifacts/pg2_core_dbsearch"; PANEL=CACHE+"/discovery/explore_panel.parquet"
TOP_N=25; RECENT_LO="2021-01"
BOOK=ROOT+"/05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results"
reg=json.load(open(ROOT+"/02_Infrastructure/factor_db/factor_registry.json",encoding="utf-8"))
panel=pd.read_parquet(PANEL)
meta=set(['ym','Ticker','score_eff','fwd_ret_1m','Size','F1','F3','F6','F12'])
allfacs=[c for c in panel.columns if c not in meta]
dirn={f:(-1.0 if reg.get(f,{}).get("direction")=="lower_better" else 1.0) for f in allfacs}
cat={f:reg.get(f,{}).get("category","other") for f in allfacs}
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas()
bc=[c for c in ("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmlr=bm.groupby("ym")[bc].apply(lambda r:np.log1p(r).sum()); bmidx=list(bmlr.index)
def bm_fwd1(t):
    if t not in bmidx: return np.nan
    i=bmidx.index(t); return np.expm1(bmlr.iloc[i+1:i+2].sum()) if i+2<=len(bmidx) else np.nan
months=sorted(panel["ym"].unique()); OOS=months[60:]
ymarr=panel["ym"].values; tk=panel["Ticker"].values; F1=panel["F1"].values
bmv={t:bm_fwd1(t) for t in OOS}
def zcs(col):
    d=panel[["ym"]].copy(); d["v"]=col
    return d.groupby("ym")["v"].transform(lambda s:(s-s.mean())/(s.std()+1e-9)).values
def active_series(sig):
    out={}; prev=set()
    for t in OOS:
        te=np.where(ymarr==t)[0]
        if len(te)<TOP_N: continue
        s=sig[te]; ok=~np.isnan(s)
        if ok.sum()<TOP_N: continue
        idx=te[ok][np.argpartition(-s[ok],min(TOP_N,ok.sum()-1))[:TOP_N]]; sel=set(tk[idx])
        gross=np.nanmean(F1[idx]); to=2*(TOP_N-len(sel&prev))/TOP_N if prev else 1.0
        b=bmv.get(t,np.nan)
        if not np.isnan(gross) and not np.isnan(b): out[t]=(gross-to*0.0015)-b
        prev=sel
    return pd.Series(out)
core_z=zcs(panel["score_eff"].values); base_act=active_series(core_z)
pr=pd.read_csv(BOOK+"/03_period_returns.csv")
pr["ym"]=(pd.to_datetime(pr["date"])-pd.offsets.MonthBegin(1)).dt.strftime("%Y-%m")
gate=pr.set_index("ym")["cash_weight"].to_dict()
def book_ir(act):
    d=act.dropna(); gd=np.array([(1.0-gate.get(t,0.0))*v for t,v in d.items()]); gd=gd[~np.isnan(gd)]
    if len(gd)<12 or gd.std()==0: return np.nan
    return gd.mean()/gd.std()*np.sqrt(12)
book_base_ir=book_ir(base_act)

# precompute per-factor zcs once (speed)
fz_cache={f:zcs(panel[f].values)*dirn[f] for f in allfacs}
core0=np.nan_to_num(core_z,nan=0.0)
rows=[]
for f in allfacs:
    fz=np.nan_to_num(fz_cache[f],nan=0.0)
    for w in (0.5,1.0):
        a=active_series(core0+w*fz); di=book_ir(a)-book_base_ir
        rows.append({"factor":f,"category":cat[f],"w":w,"book_dIR":round(di,4) if not np.isnan(di) else np.nan})
sw=pd.DataFrame(rows).dropna(subset=["book_dIR"]).sort_values("book_dIR",ascending=False)
sw.to_csv(OUT+"/phaseE_full_sweep.csv",index=False)
n=len(sw); vals=sw["book_dIR"].values
print(f"=== FULL SWEEP: {n} (factor x w) book_dIR ===")
print(f"base book IR (overlay) = {book_base_ir:.4f}")
print(f"sweep book_dIR: max={vals.max():+.4f} q99={np.percentile(vals,99):+.4f} q95={np.percentile(vals,95):+.4f} median={np.median(vals):+.4f} min={vals.min():+.4f}")
print(f"n with book_dIR>=0.05: {(vals>=0.05).sum()} ({(vals>=0.05).mean()*100:.0f}%)")
print(f"n with book_dIR>=0.10: {(vals>=0.10).sum()} ({(vals>=0.10).mean()*100:.0f}%)")
print("\n--- top 20 empirical sweep-max ---")
print(sw.head(20).to_string(index=False))
print("\n--- category breakdown of top 30 ---")
print(sw.head(30)["category"].value_counts().to_string())
# where do my survivors rank?
print("\n--- my survivors' rank in the full sweep ---")
for f,w in [("D09_Dimson_Beta",0.5),("M05_Trended_Mom",1.0),("M17_Low_52w",0.5)]:
    r=sw.reset_index(drop=True)
    m=r[(r["factor"]==f)&(r["w"]==w)]
    if len(m): print(f"  {f} w{w}: rank {m.index[0]+1}/{n}, book_dIR={m['book_dIR'].values[0]:+.4f}")
json.dump({"base_book_ir":round(book_base_ir,4),"n_sweep":n,
           "sweep_max":round(float(vals.max()),4),"sweep_q99":round(float(np.percentile(vals,99)),4),
           "sweep_q95":round(float(np.percentile(vals,95)),4),"sweep_median":round(float(np.median(vals)),4),
           "n_ge_005":int((vals>=0.05).sum()),"frac_ge_005":round(float((vals>=0.05).mean()),3),
           "top20":sw.head(20).to_dict("records")},
          open(OUT+"/phaseE_result.json","w"),indent=2)
print("\n[done] -> phaseE_full_sweep.csv + phaseE_result.json")
