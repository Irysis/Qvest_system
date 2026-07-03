"""run_fof_combine.py — 도훈 지적: FoF 시그널(family composites)을 *결합*해 멀티팩터 포트 (격리 아님).
개별 family 약해도 결합 시 diversification 효과? H=1 PIT-clean. 결합 EW vs full316 flat + placebo.
"""
import os, sys, numpy as np, pandas as pd
os.environ.setdefault("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0,"02_Infrastructure/discovery")
from discovery_explore import ensure_panel, bm_fwd_map, load_families, nw_t, HORIZONS_ALL
R=os.environ["QM_ROOT"]; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
panel=ensure_panel()
excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
fcols=[c for c in panel.columns if c not in excl]; fam,dirn=load_families(fcols)
months=sorted(panel["ym"].unique()); mi={m:i for i,m in enumerate(months)}; bmf=bm_fwd_map()
ymv=panel["ym"].values; tkv=panel["Ticker"].values
Xraw=panel[fcols].values.astype(float); Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z)
F1=panel["F1"].values.astype(float); icm=np.full((len(months),len(fcols)),np.nan)
for i,t in enumerate(months):
    m=ymv==t; y=F1[m]; ok=np.isfinite(y)
    if ok.sum()<25: continue
    yz=(y[ok]-np.nanmean(y[ok]))/(np.nanstd(y[ok])+1e-9); icm[i]=(Z[m][ok].T@yz)/ok.sum()
IC1=pd.DataFrame(icm).rolling(12,min_periods=6).mean().shift(1).values   # H=1 PIT-clean
def fam_score(family):
    fl=[f for f in fam.get(family,[]) if f in fcols]; fidx=np.array([fcols.index(f) for f in fl])
    if len(fidx)<3: return None
    sc=np.full(len(panel),np.nan)
    for i,t in enumerate(months):
        w=np.nan_to_num(IC1[i,fidx]); m=ymv==t
        if m.sum(): sc[m]=Z[m][:,fidx]@w
    return sc
def csz(s):
    o=np.full(len(s),np.nan)
    for t in np.unique(ymv):
        m=(ymv==t)&np.isfinite(s); v=s[m]
        if len(v)>5: o[m]=(v-v.mean())/(v.std()+1e-9)
    return o
def bt(score,recent=False,top_n=25):
    rec=[]; prev=set(); dec=[m for m in months[60:] if (not recent or m>='2021-01')]
    for t in dec:
        te=np.where(ymv==t)[0]; s=score[te]; ok=np.isfinite(s)
        if ok.sum()<top_n: continue
        idx=te[ok][np.argpartition(-s[ok],top_n-1)[:top_n]]; sel=set(tkv[idx])
        g=np.nanmean(panel["F1"].values[idx]); to=2*(top_n-len(sel&prev))/top_n if prev else 1.0
        rec.append((g-to*0.0015,bmf(t,1))); prev=sel
    r=pd.DataFrame(rec,columns=["net","bm"]).dropna(); a=(r.net-r.bm).values
    if len(a)<8: return None
    nav=np.cumprod(1+r.net.values); dd=1-np.min(nav/np.maximum.accumulate(nav)); cg=np.prod(1+r.net.values)**(12/len(r))-1
    return {"t":nw_t(a),"absSR":r.net.mean()/r.net.std()*np.sqrt(12),"MDD":100*dd,"Calmar":cg/dd,"n":len(a)}
FAMS=["earnings_rev","earnings","value","momentum","quality","idiovol","liquidity","growth","accrual"]
print("=== 개별 family (H=1 IC-가중 composite) ===")
famsc={}
for fmn in FAMS:
    s=fam_score(fmn)
    if s is None: continue
    famsc[fmn]=csz(s); m=bt(s); mr=bt(s,True)
    if m: print(f"  {fmn:14s} full_t={m['t']:+.2f} recent_t={mr['t'] if mr else float('nan'):+.2f} absSR={m['absSR']:.2f} Calmar={m['Calmar']:.2f}")
M=np.vstack([famsc[k] for k in famsc]).T
print("\n=== ★결합 (FoF 시그널 통합) vs 개별최고 vs full316 ===")
comb=np.nansum(M,axis=1); mE=bt(comb); mEr=bt(comb,True)
print(f"  결합-EW(family등가중)  full_t={mE['t']:+.2f} recent_t={mEr['t']:+.2f} absSR={mE['absSR']:.2f} MDD={mE['MDD']:.1f} Calmar={mE['Calmar']:.2f}")
s_full=np.full(len(panel),np.nan)
for i,t in enumerate(months):
    w=np.nan_to_num(IC1[i,:]); m=ymv==t
    if m.sum(): s_full[m]=Z[m]@w
mF=bt(s_full); mFr=bt(s_full,True)
print(f"  full316 flat(참조)     full_t={mF['t']:+.2f} recent_t={mFr['t']:+.2f} absSR={mF['absSR']:.2f} MDD={mF['MDD']:.1f} Calmar={mF['Calmar']:.2f}")
best_fam=max([bt(famsc[k])['t'] for k in famsc if bt(famsc[k])])
print(f"\n  개별최고 full_t={best_fam:.2f} | 결합-EW {mE['t']:.2f} | full316 {mF['t']:.2f}  → 결합>개별최고면 diversification 이득")
rng=np.random.RandomState(7); pl=[]; allf=np.arange(len(fcols))
for _ in range(150):
    perm=rng.permutation(allf); groups=np.array_split(perm,9); comps=[]
    for g in groups:
        sc=np.full(len(panel),np.nan)
        for i,t in enumerate(months):
            w=np.nan_to_num(IC1[i,g]); m=ymv==t
            if m.sum(): sc[m]=Z[m][:,g]@w
        comps.append(csz(sc))
    cb=np.nansum(np.vstack(comps).T,axis=1); r=bt(cb)
    if r: pl.append(r['t'])
pl=np.array(pl); print(f"\n  placebo(결합 vs 랜덤9그룹결합 150): full_t {mE['t']:.2f} → {(pl<mE['t']).mean()*100:.1f}%ile (pl95={np.percentile(pl,95):.2f})")
print("saved."); pd.DataFrame([{"m":"combine_EW","t":mE['t'],"absSR":mE['absSR'],"Calmar":mE['Calmar']},{"m":"full316","t":mF['t'],"absSR":mF['absSR'],"Calmar":mF['Calmar']}]).to_csv(OUT+"/fof_combine_results.csv",index=False)
