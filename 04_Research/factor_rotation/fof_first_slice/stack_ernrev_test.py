"""stack_ernrev_test.py — 결정 게이트: earnings_rev@3M sleeve가 FoF 북과 stack되나?
빌드: earnings_rev@3M(monthly-overlapping 3tranche) + score_eff@1M(prod proxy) sleeve active 시계열.
측정: 각 sleeve standalone PORT_t(full/recent) + active-ρ 행렬 + 2/3-sleeve stack book-IR/PORT_t.
게이트: ρ(FoF,er3)<0.25 ∧ er3 PORT_t 통과 → stacking load-bearing. (in-sample Sharpe-max는 낙관 라벨.)
"""
import sys, os
os.environ.setdefault("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0,"02_Infrastructure/discovery")
from discovery_explore import ensure_panel, bm_fwd_map, load_families, nw_t, HORIZONS_ALL
import pandas as pd, numpy as np
ROOT=os.environ["QM_ROOT"]; OUT=ROOT+"/04_Research/factor_rotation/fof_first_slice"

panel=ensure_panel()
excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
fcols=[c for c in panel.columns if c not in excl]
fam,dirn=load_families(fcols)
ernrev=fam["earnings_rev"]; print("earnings_rev factors:",ernrev)
panel["sig_er"]=panel[ernrev].fillna(0.0).values@np.array([dirn.get(f,1.0) for f in ernrev])
panel["sig_se"]=panel["score_eff"].fillna(0.0).values
bmf=bm_fwd_map(); months=sorted(panel["ym"].unique()); mi={m:i for i,m in enumerate(months)}
f1_by_month={t:dict(zip(d["Ticker"],d["F1"])) for t,d in panel.groupby("ym")}

def overlap_sleeve(sigcol,K,top_n=25,start=60):
    hold={}
    for t,d in panel.groupby("ym"):
        s=d[sigcol].values; tk=d["Ticker"].values; ok=~np.isnan(s)
        if ok.sum()<top_n: continue
        idx=np.argpartition(-s[ok],top_n-1)[:top_n]; hold[t]=set(tk[ok][idx])
    rec=[]; prevw={}
    for t in months[start:]:
        i=mi[t]; forms=[months[i-k] for k in range(K) if i-k>=0]; forms=[f for f in forms if f in hold]
        if not forms: continue
        wt={}
        for f in forms:
            for nm in hold[f]: wt[nm]=wt.get(nm,0.0)+1.0/(K*top_n)
        f1m=f1_by_month.get(t,{}); r=0.0; tw=0.0
        for nm,wv in wt.items():
            v=f1m.get(nm)
            if v is not None and not np.isnan(v): r+=wv*v; tw+=wv
        if tw<=0: continue
        r/=tw
        allk=set(wt)|set(prevw); to=sum(abs(wt.get(k,0.0)-prevw.get(k,0.0)) for k in allk)
        bm=bmf(t,1)
        rec.append((t,r-0.0015*to,bm,to)); prevw=wt
    df=pd.DataFrame(rec,columns=["ym","net","bm","to"]).dropna(subset=["net","bm"])
    df["act"]=df["net"]-df["bm"]; return df

er3=overlap_sleeve("sig_er",3); se1=overlap_sleeve("sig_se",1)
print(f"er3(earnings_rev@3M): n={len(er3)} TO={er3.to.mean()*12:.0f}%/yr | se1(score_eff@1M): n={len(se1)} TO={se1.to.mean()*12:.0f}%/yr")

fof=pd.read_csv(OUT+"/stack_fof_active.csv")
M=(fof[["ym","act_fof"]]
   .merge(er3[["ym","act"]].rename(columns={"act":"act_er3"}),on="ym")
   .merge(se1[["ym","act"]].rename(columns={"act":"act_se1"}),on="ym")).dropna()
print(f"\nmerged: n={len(M)} {M.ym.min()}..{M.ym.max()}")

def ir(a): a=a[~np.isnan(a)]; return a.mean()/a.std()*np.sqrt(12) if a.std()>0 else np.nan
def sub(a,lo): return (M[a] if lo is None else M.loc[M.ym>=lo,a]).values
print("\n=== sleeve standalone (active vs cap-weight BM) ===")
for a,nm in [("act_fof","FoF(1M IC-w)"),("act_er3","earnings_rev@3M"),("act_se1","score_eff@1M")]:
    print(f"  {nm:16s} full: PORT_t={nw_t(sub(a,None)):+.2f} IR={ir(sub(a,None)):+.2f} | recent(2021+): PORT_t={nw_t(sub(a,'2021-01')):+.2f} IR={ir(sub(a,'2021-01')):+.2f}")

print("\n=== active-return 상관 ρ (full / recent 2021+) ===")
cf=M[["act_fof","act_er3","act_se1"]].corr(); cr=M.loc[M.ym>='2021-01',["act_fof","act_er3","act_se1"]].corr()
print("  full:  ρ(FoF,er3)=%.2f  ρ(FoF,se1)=%.2f  ρ(er3,se1)=%.2f"%(cf.loc["act_fof","act_er3"],cf.loc["act_fof","act_se1"],cf.loc["act_er3","act_se1"]))
print("  recent:ρ(FoF,er3)=%.2f  ρ(FoF,se1)=%.2f  ρ(er3,se1)=%.2f"%(cr.loc["act_fof","act_er3"],cr.loc["act_fof","act_se1"],cr.loc["act_er3","act_se1"]))

def stack(cols,lo=None,w=None):
    A=(M[cols] if lo is None else M.loc[M.ym>=lo,cols]).values
    if w is None: w=np.ones(A.shape[1])/A.shape[1]
    s=A@w; return nw_t(s), ir(s)
def sharpe_max(cols):  # long-only simplex grid (in-sample 낙관 라벨)
    A=M[cols].values; best=(-9,None)
    if A.shape[1]==2:
        for a in np.linspace(0,1,21):
            w=np.array([a,1-a]); s=A@w; v=ir(s)
            if v>best[0]: best=(v,w)
    else:
        for a in np.linspace(0,1,11):
            for b in np.linspace(0,1-a,int((1-a)*10)+1):
                w=np.array([a,b,1-a-b]); s=A@w; v=ir(s)
                if v>best[0]: best=(v,w)
    return best
print("\n=== stacking (EW = 정직 baseline / Sharpe-max = in-sample 낙관) ===")
for label,cols in [("FoF+er3(2-sleeve)",["act_fof","act_er3"]),("FoF+er3+se1(3-sleeve)",["act_fof","act_er3","act_se1"])]:
    t,i=stack(cols); tr,ir_r=stack(cols,'2021-01'); v,w=sharpe_max(cols)
    print(f"  [{label:22s}] EW: full PORT_t={t:+.2f} IR={i:+.2f} | recent IR={ir_r:+.2f} || Sharpe-max IR={v:+.2f} w={np.round(w,2)}")
print(f"\n  단일 최고(FoF full IR={ir(sub('act_fof',None)):+.2f}) 대비 stack IR 상승분이 실질 = book-IR 산식 i·√(K/(1+(K-1)ρ)) 검증.")
M.to_csv(OUT+"/stack_series.csv",index=False); print("\nsaved stack_series.csv")
