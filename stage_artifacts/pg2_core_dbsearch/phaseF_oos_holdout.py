"""
PG2 Phase F: IS/OOS holdout on the sweep — the decisive lever-vs-artifact test.
Select each factor's best-w by book_dIR on IS (2010-2018), then MEASURE that same
(factor,w) book_dIR on OOS (2019-2026). If the sweep-top is a real lever, IS winners
carry to OOS. If argmax-mining, IS-OOS correlation ~0 and IS-selected top decays to ~0.
Also: is ANY single factor's book_dIR positive in BOTH halves (durable)?
"""
import pandas as pd, numpy as np, json, os, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
from scipy import stats
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"
OUT=ROOT+"/stage_artifacts/pg2_core_dbsearch"; PANEL=CACHE+"/discovery/explore_panel.parquet"
TOP_N=25; IS_HI="2018-12"; OOS_LO="2019-01"
BOOK=ROOT+"/05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results"
reg=json.load(open(ROOT+"/02_Infrastructure/factor_db/factor_registry.json",encoding="utf-8"))
panel=pd.read_parquet(PANEL)
meta=set(['ym','Ticker','score_eff','fwd_ret_1m','Size','F1','F3','F6','F12'])
allfacs=[c for c in panel.columns if c not in meta]
dirn={f:(-1.0 if reg.get(f,{}).get("direction")=="lower_better" else 1.0) for f in allfacs}
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
def book_ir_seg(act,lo=None,hi=None):
    d=act.dropna()
    if lo: d=d[d.index>=lo]
    if hi: d=d[d.index<=hi]
    gd=np.array([(1.0-gate.get(t,0.0))*v for t,v in d.items()]); gd=gd[~np.isnan(gd)]
    if len(gd)<10 or gd.std()==0: return np.nan
    return gd.mean()/gd.std()*np.sqrt(12)
base_is=book_ir_seg(base_act,hi=IS_HI); base_oos=book_ir_seg(base_act,lo=OOS_LO)
print(f"base book IR: IS={base_is:.4f} OOS={base_oos:.4f}")
core0=np.nan_to_num(core_z,nan=0.0)
rows=[]
for f in allfacs:
    fz=np.nan_to_num(zcs(panel[f].values)*dirn[f],nan=0.0)
    best=None
    for w in (0.5,1.0):
        a=active_series(core0+w*fz)
        dis=book_ir_seg(a,hi=IS_HI)-base_is
        doos=book_ir_seg(a,lo=OOS_LO)-base_oos
        if np.isnan(dis) or np.isnan(doos): continue
        if best is None or dis>best[1]: best=(w,dis,doos)
    if best: rows.append({"factor":f,"w":best[0],"IS_dIR":round(best[1],4),"OOS_dIR":round(best[2],4)})
d=pd.DataFrame(rows)
d.to_csv(OUT+"/phaseF_oos_holdout.csv",index=False)
# IS-OOS correlation across factors (the artifact test)
rho,pv=stats.spearmanr(d["IS_dIR"],d["OOS_dIR"])
print(f"\nIS-OOS book_dIR Spearman across {len(d)} factors: rho={rho:+.3f} (p={pv:.3f})")
# top-decile by IS -> mean OOS
n=len(d); topk=max(5,n//10)
top=d.sort_values("IS_dIR",ascending=False).head(topk)
print(f"IS-top-{topk} (by IS_dIR): mean IS_dIR={top['IS_dIR'].mean():+.4f} -> mean OOS_dIR={top['OOS_dIR'].mean():+.4f}")
print(f"  of IS-top-{topk}, n with OOS_dIR>=0.05: {(top['OOS_dIR']>=0.05).sum()}/{topk}")
# durable: positive in BOTH halves at >=0.05
dur=d[(d["IS_dIR"]>=0.05)&(d["OOS_dIR"]>=0.05)]
print(f"\nDURABLE (book_dIR>=0.05 in BOTH IS and OOS): {len(dur)} factors")
if len(dur): print(dur.sort_values("OOS_dIR",ascending=False).head(15).to_string(index=False))
# where do my survivors land
print("\n--- survivors IS vs OOS ---")
for f in ["D09_Dimson_Beta","M05_Trended_Mom","M17_Low_52w","V15_NetDebt_Adj_EP","C07_TP_Mom","IN03_RD_to_Market"]:
    m=d[d["factor"]==f]
    if len(m): print(f"  {f} w{m['w'].values[0]}: IS_dIR={m['IS_dIR'].values[0]:+.4f} OOS_dIR={m['OOS_dIR'].values[0]:+.4f}")
json.dump({"base_is":round(base_is,4),"base_oos":round(base_oos,4),
           "is_oos_spearman":round(float(rho),3),"is_oos_p":round(float(pv),3),
           "n_factors":n,"is_top_decile_mean_oos":round(float(top['OOS_dIR'].mean()),4),
           "n_durable_both_005":int(len(dur)),
           "durable":dur.sort_values("OOS_dIR",ascending=False).to_dict("records")},
          open(OUT+"/phaseF_result.json","w"),indent=2)
print("\n[done] -> phaseF_oos_holdout.csv + phaseF_result.json")
