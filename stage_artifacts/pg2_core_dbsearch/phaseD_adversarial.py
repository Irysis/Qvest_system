"""
PG2 core DB-wide search — Phase D: adversarial gauntlet on top survivors.

sweep of 327f -> multiple-testing. Validate the top book_dIR survivors against:
  1. PLACEBO: add a RANDOM DB factor to core at same w; does its book_dIR distribution
     already reach the survivor's? (if survivor is not in top tail -> sweep artifact)
  2. lag1-stress: shift signal +1 month (was the lift a fast-decay/lookahead artifact?)
  3. subperiod: is the full-period lift concentrated in one regime?
  4. double-count check: is the lift orthogonal to the M4/R05 overlay, or does the overlay
     already capture it? (correlate the (variant-base) active delta with the overlay cash-gate)
  5. DSR on the book_dIR sweep (selection = argmax over 327f).
"""
import pandas as pd, numpy as np, json, os, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
from scipy import stats
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"
OUT=ROOT+"/stage_artifacts/pg2_core_dbsearch"; PANEL=CACHE+"/discovery/explore_panel.parquet"
RECENT_LO="2021-01"; TOP_N=25; np.random.seed(42)
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
def nw_t(x,lag=3):
    x=x[~np.isnan(x)]; n=len(x)
    if n<5: return np.nan
    e=x-x.mean(); s=(e@e)/n
    for l in range(1,lag+1): s+=2*(1-l/(lag+1))*((e[l:]@e[:-l])/n)
    return x.mean()/np.sqrt(s/n) if s>0 else np.nan
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
core_z=zcs(panel["score_eff"].values)
base_act=active_series(core_z)

pr=pd.read_csv(BOOK+"/03_period_returns.csv")
pr["ym"]=(pd.to_datetime(pr["date"])-pd.offsets.MonthBegin(1)).dt.strftime("%Y-%m")
gate=pr.set_index("ym")["cash_weight"].to_dict()
def book_ir(act):
    d=act.dropna(); gd=np.array([(1.0-gate.get(t,0.0))*v for t,v in d.items()]); gd=gd[~np.isnan(gd)]
    if len(gd)<12 or gd.std()==0: return np.nan
    return gd.mean()/gd.std()*np.sqrt(12)
book_base_ir=book_ir(base_act)

def integ_act(f,w,lag=0):
    col=panel[f].values.copy()
    if lag>0:
        # shift signal forward by lag months within ticker (stress)
        d=panel[["ym","Ticker"]].copy(); d["v"]=col*dirn[f]
        d["vz"]=d.groupby("ym")["v"].transform(lambda s:(s-s.mean())/(s.std()+1e-9))
        d=d.sort_values(["Ticker","ym"]); d["vz"]=d.groupby("Ticker")["vz"].shift(lag)
        fz=d.sort_index()["vz"].values
    else:
        fz=zcs(col)*dirn[f]
    sig=np.nan_to_num(core_z,nan=0.0)+w*np.nan_to_num(fz,nan=0.0)
    return active_series(sig)

TOPS=[("D09_Dimson_Beta",0.5),("M05_Trended_Mom",1.0),("M17_Low_52w",0.5)]
report={}

# ---- 1. PLACEBO: random single-factor add to core at w, book_dIR distribution ----
print("=== PLACEBO: 300 random DB-factor adds to core (book_dIR) ===")
for f,w in TOPS:
    surv_act=integ_act(f,w); surv_dir=book_ir(surv_act)-book_base_ir
    pl=[]
    for _ in range(300):
        rf=np.random.choice(allfacs)
        a=integ_act(rf,w)
        di=book_ir(a)-book_base_ir
        if not np.isnan(di): pl.append(di)
    pl=np.array(pl); pct=(pl<surv_dir).mean()*100
    print(f"  {f} w{w}: book_dIR={surv_dir:+.4f} | placebo pctile={pct:.1f}% (q95={np.percentile(pl,95):+.4f}, q99={np.percentile(pl,99):+.4f}, mean={pl.mean():+.4f})")
    report[f"placebo_{f}_{w}"]={"book_dIR":round(surv_dir,4),"pctile":round(pct,1),
        "placebo_q95":round(float(np.percentile(pl,95)),4),"placebo_q99":round(float(np.percentile(pl,99)),4),
        "placebo_mean":round(float(pl.mean()),4),"n_placebo":len(pl)}

# ---- 2. lag1-stress ----
print("\n=== lag1-stress (shift signal +1m) ===")
for f,w in TOPS:
    a0=integ_act(f,w); a1=integ_act(f,w,lag=1)
    common=base_act.index.intersection(a0.index)
    d0=book_ir(a0)-book_base_ir
    common1=base_act.index.intersection(a1.index)
    d1=book_ir(a1)-book_base_ir
    print(f"  {f} w{w}: book_dIR lag0={d0:+.4f} -> lag1={d1:+.4f}")
    report[f"lag1_{f}_{w}"]={"lag0":round(d0,4),"lag1":round(d1,4)}

# ---- 3. subperiod (full-period active IR of the delta) ----
print("\n=== subperiod: (variant-base) active-delta IR by era ===")
def seg_ir(delta,lo,hi):
    d=delta[(delta.index>=lo)&(delta.index<=hi)].values; d=d[~np.isnan(d)]
    if len(d)<8: return np.nan
    return round(d.mean()/d.std()*np.sqrt(12),3)
for f,w in TOPS:
    a=integ_act(f,w); common=base_act.index.intersection(a.index)
    delta=a[common]-base_act[common]
    s=[seg_ir(delta,"2010-01","2015-12"),seg_ir(delta,"2016-01","2020-12"),seg_ir(delta,"2021-01","2026-12")]
    print(f"  {f} w{w}: 2010-15 IR={s[0]} | 2016-20 IR={s[1]} | 2021-26 IR={s[2]}")
    report[f"subperiod_{f}_{w}"]={"2010_2015":s[0],"2016_2020":s[1],"2021_2026":s[2]}

# ---- 4. double-count check: corr of (variant-base) active delta with overlay cash-gate ----
print("\n=== double-count: corr(active-delta, overlay invested-frac) ===")
inv=pd.Series({t:1.0-gate.get(t,np.nan) for t in base_act.index}).dropna()
for f,w in TOPS:
    a=integ_act(f,w); common=base_act.index.intersection(a.index).intersection(inv.index)
    delta=(a[common]-base_act[common])
    cc=delta.corr(inv[common])
    print(f"  {f} w{w}: corr(delta, invested_frac)={cc:+.3f}  (high +ve = overlay AMPLIFIES delta; strong -ve = overlay KILLS it)")
    report[f"doublecount_{f}_{w}"]={"corr_delta_invested":round(cc,3)}

# ---- 5. DSR on book_dIR sweep (327 factors argmax) ----
# expected max under null across n_trials; DSR = P(SR>0 | selection).
# Use the placebo book_dIR distribution std as null; n_trials = 327 (single-factor sweep).
print("\n=== DSR (sweep 327f, book_dIR) ===")
# gather full placebo of best (D09) for null variance
best_f,best_w=TOPS[0]; surv_dir=book_ir(integ_act(best_f,best_w))-book_base_ir
plall=[]
for _ in range(300):
    rf=np.random.choice(allfacs); di=book_ir(integ_act(rf,best_w))-book_base_ir
    if not np.isnan(di): plall.append(di)
plall=np.array(plall); n_trials=327
# expected max of n_trials draws from placebo dist (Gumbel approx)
mu,sd=plall.mean(),plall.std()
emax=mu+sd*(np.sqrt(2*np.log(n_trials)))
print(f"  best book_dIR={surv_dir:+.4f} | placebo mu={mu:+.4f} sd={sd:.4f} | E[max of {n_trials}]={emax:+.4f}")
print(f"  -> best {'EXCEEDS' if surv_dir>emax else 'WITHIN'} expected-max-under-null (sweep-adjusted)")
report["DSR_sweep"]={"best_book_dIR":round(surv_dir,4),"placebo_mu":round(mu,4),"placebo_sd":round(sd,4),
    "n_trials":n_trials,"expected_max_null":round(float(emax),4),"exceeds_null_max":bool(surv_dir>emax)}

json.dump(report,open(OUT+"/phaseD_adversarial.json","w"),indent=2)
print("\n[done] -> phaseD_adversarial.json")
