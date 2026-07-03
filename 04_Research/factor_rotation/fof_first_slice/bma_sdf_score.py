"""bma_sdf_score.py MODE — Bryzgalova-Huang-Julliard (2023) "Bayesian Solutions for the Factor Zoo"
spike-and-slab BMA-SDF 충실 구현 (PC-공간 닫힌형 marginalized posterior).
KNS와 동일 substrate(managed 팩터 Fₜ=Z'r/N, μ̄,Σ, 시장직교화). KNS ridge와 차이 = **명시적 factor 선택 + BMA**.
PC-공간(BHJ "sparse in PCs"): Σ=QDQ', μ_P=Q'μ̄, PC j 우도 μ_P,j~N(dⱼ b_P,j, dⱼ/T).
  spike-and-slab: b_P,j | inc ~ N(0,ψ), | exc = 0. Bayes factor로 포함확률 pⱼ:
    L_exc=N(μ_P,j;0,dⱼ/T), L_inc=N(μ_P,j;0,dⱼ²ψ+dⱼ/T), pⱼ=πL_inc/(πL_inc+(1−π)L_exc)
  BMA 사후평균 b̂_P,j = pⱼ·[ψ/(dⱼψ+1/T)]·μ_P,j (marginalize γ 해석적). b̂=Q b̂_P, 종목점수 s=Z b̂.
하이퍼(π,ψ): 3-fold CV(eq.30 R²_oos)로 선택 — KNS γ와 동일 프로토콜. PIT 확장윈도우 연간 refit.
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
elif MODE=="allliq": mask=(M.nret>=15)&(~M.bad)&(M.adv>=2e8)
else: raise SystemExit("MODE?")
panel=M[mask].copy(); months=sorted(panel.ym.unique()); T=len(months)
ymv=panel.ym.values; tkv=panel.Ticker.values; F1=panel.F1.values.astype(float)
bench=pd.read_parquet(OUT+"/kns_master_bench.parquet"); bench["ym"]=pd.to_datetime(bench.Date).dt.to_period("M").astype(str)
bmap=dict(zip(bench.ym,bench.BM_Ret))
Lg(f"[BMA {MODE}] rows {len(panel)} T={T} median N {int(panel.groupby('ym').size().median())} H={H}")
Xraw=panel[FCOLS].values.astype(float); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1.0; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z)
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
def logN(x,var): return -0.5*(np.log(2*np.pi*var)+x*x/var)
def bma_b(mu,C,Tw,pi,psi):
    """PC-공간 spike-and-slab BMA 사후평균 b̂ (H,)."""
    d,Q=np.linalg.eigh(C); d=d[::-1]; Q=Q[:,::-1]
    keep=d>1e-12*d.max(); d=d[keep]; Q=Q[:,keep]
    muP=Q.T@mu; s2=d/Tw               # PC 우도분산 dⱼ/T
    Lexc=logN(muP,s2); Linc=logN(muP,d*d*psi+s2)
    # 포함확률 (log-sum-exp)
    a=np.log(pi)+Linc; b=np.log(1-pi)+Lexc; mx=np.maximum(a,b)
    p=np.exp(a-mx)/(np.exp(a-mx)+np.exp(b-mx))
    shrink=psi/(d*psi+1.0/Tw)         # 포함시 사후평균 계수 (×μP)
    bP=p*shrink*muP
    return Q@bP, int((p>0.5).sum()), len(d)
def r2(mu2,C2,b): e=mu2-C2@b; return 1.0-(e@e)/(mu2@mu2)
def cv_hyper(Fm, pis, psis, K=3):
    rng=np.random.RandomState(0); idx=rng.permutation(Fm.shape[0]); fo=np.array_split(idx,K)
    best=-1e18; bp=(pis[len(pis)//2],psis[len(psis)//2])
    for pi in pis:
        for psi in psis:
            acc=[]
            for f in range(K):
                te=fo[f]; tr=np.concatenate([fo[j] for j in range(K) if j!=f]); mt,Ct=mom(Fm[tr]); me,Ce=mom(Fm[te])
                bb,_,_=bma_b(mt,Ct,len(tr),pi,psi); acc.append(r2(me,Ce,bb))
            a=np.mean(acc)
            if a>best: best=a; bp=(pi,psi)
    return bp,best

min_hist=60; refit=12
def ym2date(ym): return pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0)
kk_all=[k for k in range(T) if np.isfinite(mfr[k]).all()]
Fo=orth(mfr[kk_all],mkt[kk_all]); tau=np.trace(mom(Fo)[1])/H
pis=[0.05,0.1,0.2,0.4]; psis=np.logspace(-2,4,20)*tau  # slab 분산 grid (τ 스케일)
rows=[]; cur=None; diag=[]
for m in range(min_hist,T):
    mm=months[m]; idx=[k for k in range(m) if np.isfinite(mfr[k]).all()]
    if len(idx)<min_hist: continue
    Fm=orth(mfr[idx],mkt[idx]); mu_,C_=mom(Fm); tau_=np.trace(C_)/H
    if (m-min_hist)%refit==0 or cur is None:
        (pi_,psi_),cvr=cv_hyper(Fm,pis,psis*(tau_/tau) if tau>0 else psis)
        cur=(pi_,psi_); bb,ninc,npc=bma_b(mu_,C_,len(idx),pi_,psi_); diag.append((mm,pi_,psi_/tau_,ninc,npc,cvr))
    bb,_,_=bma_b(mu_,C_,len(idx),cur[0],cur[1])
    ms=ymv==mm; s=Z[ms]@bb
    for tk,a in zip(tkv[ms],s): rows.append((ym2date(mm),tk,a))
d=pd.DataFrame(rows,columns=["Date","Ticker","score"]); d.to_parquet(OUT+f"/scores_BMA_{MODE}.parquet",index=False)
dg=pd.DataFrame(diag,columns=["refit","pi","psi_over_tau","n_incl","n_pc","cv_r2"])
Lg(f"[BMA {MODE}] 결정월 {d.Date.nunique()} | refit 예: "+dg.round(3).tail(3).to_string(index=False).replace("\n"," | "))
d2=d.copy(); d2["ym"]=pd.to_datetime(d2.Date).dt.to_period("M").astype(str); ics=[]
for ym,g in d2.groupby("ym"):
    ms=ymv==ym; y=pd.Series(F1[ms],index=tkv[ms]); c=pd.concat([g.set_index("Ticker")["score"],y],axis=1).dropna()
    if len(c)>25 and c.iloc[:,0].std()>1e-9: ics.append(np.corrcoef(c.iloc[:,0],c.iloc[:,1])[0,1])
ics=np.array(ics); Lg(f"[BMA {MODE}] PIT IC mean={ics.mean():+.4f} ICIR={ics.mean()/ics.std()*np.sqrt(12):+.2f} n={len(ics)} → scores_BMA_{MODE}.parquet")
