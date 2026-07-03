"""score_kns_universe.py MODE — master 패널에 KNS 충실 추정(Phase A 요약 + Phase B PIT 스코어)을 모드 유니버스로 적용.
MODE ∈ {canonical, allclean, allliq}:
  canonical = K200∪KQ150 | allclean = factor-covered ∩ 거래일≥15 ∩ ~결함 | allliq = allclean ∩ adv≥2e8
유니버스 = 추정(Z_std·managed F=Z'R) + 선택 동일 cross-section. 산출: kns_scores_{L2,PCsparse}_{MODE}.parquet + kns_ret_{MODE}/kns_liq_{MODE}.parquet
KNS 원전: eq.13-14 μ̄,Σ / eq.22 b̂=(Σ+γI)⁻¹μ̄ / eq.30 3-fold CV / PC-sparse. 시장직교화. 종목점수 s=Z·b̂.
"""
import os, sys, numpy as np, pandas as pd
def Lg(*a): print(*a,flush=True)
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; os.environ.setdefault("QM_ROOT",R)
sys.path.insert(0,R+"/02_Infrastructure/discovery")
from discovery_explore import ensure_panel, HORIZONS_ALL
OUT=R+"/04_Research/factor_rotation/fof_first_slice"
MODE=sys.argv[1] if len(sys.argv)>1 else "allclean"
_p=ensure_panel(); excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
FCOLS=[c for c in _p.columns if c not in excl]; H=len(FCOLS)

M=pd.read_parquet(OUT+"/kns_master_panel.parquet")
if MODE=="canonical": mask=(M.K200f|M.KQ150f)
elif MODE=="allclean": mask=(M.nret>=15)&(~M.bad)
elif MODE=="allliq":   mask=(M.nret>=15)&(~M.bad)&(M.adv>=2e8)
else: raise SystemExit("MODE?")
panel=M[mask].copy(); Lg(f"[{MODE}] rows {len(panel)} | median N/월 {int(panel.groupby('ym').size().median())}")
bench=pd.read_parquet(OUT+"/kns_master_bench.parquet"); bench["ym"]=pd.to_datetime(bench.Date).dt.to_period("M").astype(str)
bmap=dict(zip(bench.ym,bench.BM_Ret))
months=sorted(panel.ym.unique()); T=len(months); ymv=panel.ym.values; tkv=panel.Ticker.values
Xraw=panel[FCOLS].values.astype(float); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1.0; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z); F1=panel.F1.values.astype(float)
mfr=np.full((T,H),np.nan)
for k,t in enumerate(months):
    m=ymv==t; r=F1[m]; ok=np.isfinite(r)
    if ok.sum()<25: continue
    mfr[k]=(Z[m][ok].T@r[ok])/ok.sum()
mkt=np.array([bmap.get(mm,np.nan) for mm in months])
def orth(Fm,mk):
    ok=np.isfinite(mk)
    if ok.sum()<10: return Fm.copy()
    mk2=mk.copy(); mk2[~ok]=np.nanmean(mk[ok]); mkc=mk2-mk2.mean(); den=mkc@mkc
    if den<1e-12: return Fm.copy()
    return Fm-np.outer(mkc,(Fm-Fm.mean(0)).T@mkc/den)
def mom(Fm): mu=Fm.mean(0); return mu,(Fm-mu).T@(Fm-mu)/Fm.shape[0]
def r2(mu2,C2,b): e=mu2-C2@b; return 1.0-(e@e)/(mu2@mu2)
def cvg(Fm,gs,K=3):
    rng=np.random.RandomState(0); idx=rng.permutation(Fm.shape[0]); fo=np.array_split(idx,K); best=-1e18; bg=gs[-1]
    for g in gs:
        acc=[]
        for f in range(K):
            te=fo[f]; tr=np.concatenate([fo[j] for j in range(K) if j!=f]); mt,Ct=mom(Fm[tr]); me,Ce=mom(Fm[te])
            acc.append(r2(me,Ce,np.linalg.solve(Ct+g*np.eye(H),mt)))
        a=np.mean(acc)
        if a>best: best=a; bg=g
    return bg,best
def cvk(Fm,gs,ks,K=3):
    rng=np.random.RandomState(1); idx=rng.permutation(Fm.shape[0]); fo=np.array_split(idx,K)
    F=[]
    for f in range(K):
        te=fo[f]; tr=np.concatenate([fo[j] for j in range(K) if j!=f]); mt,Ct=mom(Fm[tr]); me,Ce=mom(Fm[te])
        d,Q=np.linalg.eigh(Ct); d=d[::-1]; Q=Q[:,::-1]; F.append((mt,me,Ce,d,Q))
    best=-1e18; bk=ks[0]
    for k in ks:
        acc=[]
        for (mt,me,Ce,d,Q) in F:
            Qk=Q[:,:k]; dk=np.where(d[:k]>1e-12,d[:k],1e-12); acc.append(r2(me,Ce,Qk@((Qk.T@mt)/(dk+gs))))
        a=np.mean(acc)
        if a>best: best=a; bk=k
    return bk,best
# Phase A 요약
kk_all=[k for k in range(T) if np.isfinite(mfr[k]).all()]
Fo=orth(mfr[kk_all],mkt[kk_all]); mu,C=mom(Fo); tau=np.trace(C)
gA=np.logspace(-4,5,80)*(tau/H); gs_star,cvA=cvg(Fo,gA); k_star,cvKA=cvk(Fo,gs_star,[1,2,3,5,8,12,20,40])
bL2f=np.linalg.solve(C+gs_star*np.eye(H),mu); sr2=mu@bL2f
Lg(f"[{MODE} Phase A] Tm={len(kk_all)} γ*/mean_eig={gs_star/(tau/H):.1f} CV_L2={cvA:+.4f} PCsparse k={k_star} R²={cvKA:+.4f} 함의annualSR≈{np.sqrt(max(sr2,0)*12):.2f}")
# Phase B PIT
min_hist=60; refit=12; gsB=np.logspace(-4,5,60)
rl2=[]; rpc=[]; cur_g=None; cur_k=None
def ym2date(ym): return pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0)
for m in range(min_hist,T):
    mm=months[m]; kk=[k for k in range(m) if np.isfinite(mfr[k]).all()]
    if len(kk)<min_hist: continue
    Fm=orth(mfr[kk],mkt[kk]); mu_,C_=mom(Fm); tau_=np.trace(C_)
    if (m-min_hist)%refit==0 or cur_g is None:
        cur_g,_=cvg(Fm,gsB*(tau_/H)); cur_k,_=cvk(Fm,cur_g,[1,2,3,5,8,12,20,40])
    bL2=np.linalg.solve(C_+cur_g*np.eye(H),mu_)
    d,Q=np.linalg.eigh(C_); d=d[::-1]; Q=Q[:,::-1]; Qk=Q[:,:cur_k]; dk=np.where(d[:cur_k]>1e-12,d[:cur_k],1e-12); bPC=Qk@((Qk.T@mu_)/(dk+cur_g))
    ms=ymv==mm; zt=Z[ms]; dt=ym2date(mm)
    for tk,a,b in zip(tkv[ms],zt@bL2,zt@bPC): rl2.append((dt,tk,a)); rpc.append((dt,tk,b))
dL2=pd.DataFrame(rl2,columns=["Date","Ticker","score"]); dPC=pd.DataFrame(rpc,columns=["Date","Ticker","score"])
dL2.to_parquet(OUT+f"/kns_scores_L2_{MODE}.parquet",index=False); dPC.to_parquet(OUT+f"/kns_scores_PCsparse_{MODE}.parquet",index=False)
# 모드 유니버스 계약입력(ret/liq) — 벤치는 master 공유
rr=panel[["Ticker","ym","F1"]].dropna(subset=["F1"]).copy(); rr["Date"]=rr.ym.map(ym2date)
rr[["Date","Ticker","F1"]].rename(columns={"F1":"Ret_1m"}).to_parquet(OUT+f"/kns_ret_{MODE}.parquet",index=False)
ld=panel[["Ticker","ym","adv"]].dropna(subset=["adv"]).copy(); ld["Date"]=ld.ym.map(ym2date)
ld[["Date","Ticker","adv"]].to_parquet(OUT+f"/kns_liq_{MODE}.parquet",index=False)
# PIT IC
ics=[]; dd=dL2.copy(); dd["ym"]=pd.to_datetime(dd.Date).dt.to_period("M").astype(str)
for ym,g in dd.groupby("ym"):
    ms=ymv==ym; y=pd.Series(F1[ms],index=tkv[ms]); s=g.set_index("Ticker")["score"]; c=pd.concat([s,y],axis=1).dropna()
    if len(c)>25 and c.iloc[:,0].std()>1e-9: ics.append(np.corrcoef(c.iloc[:,0],c.iloc[:,1])[0,1])
ics=np.array(ics); Lg(f"[{MODE} PIT IC L2] mean={ics.mean():+.4f} ICIR={ics.mean()/ics.std()*np.sqrt(12):+.2f} n={len(ics)} 결정월 {dL2.Date.nunique()}")
Lg(f"saved kns_scores_*_{MODE}.parquet")
