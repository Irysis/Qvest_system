"""run_kns_canonical_scores.py — KNS 충실 구현 (canonical 유니버스, 2005-01..2026-06).
Phase A(full-sample 복제 요약) + Phase B(PIT 확장윈도우 배포 슈퍼팩터: L2 eq.22 + PC-sparse).
입력: kns_canonical_panel.parquet(ym,Ticker,327chars,F1) + kns_bench.parquet(forward BM).
산출: kns_scores_L2_canon.parquet / kns_scores_PCsparse_canon.parquet (Date,Ticker,score) → C단계 R 계약백테.
"""
import os, sys, numpy as np, pandas as pd
try: os.environ["OMP_NUM_THREADS"]="1"; os.environ["OPENBLAS_NUM_THREADS"]="1"; os.environ["MKL_NUM_THREADS"]="1"
except: pass
def L(*a): print(*a,flush=True)
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; os.environ.setdefault("QM_ROOT",R)
sys.path.insert(0,R+"/02_Infrastructure/discovery")
from discovery_explore import ensure_panel, HORIZONS_ALL
OUT=R+"/04_Research/factor_rotation/fof_first_slice"

_p=ensure_panel(); excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
FCOLS=[c for c in _p.columns if c not in excl]; H=len(FCOLS)
panel=pd.read_parquet(OUT+"/kns_canonical_panel.parquet")
months=sorted(panel.ym.unique()); T=len(months); mi={m:i for i,m in enumerate(months)}
ymv=panel.ym.values; tkv=panel.Ticker.values
bench=pd.read_parquet(OUT+"/kns_bench.parquet"); bench["ym"]=pd.to_datetime(bench.Date).dt.to_period("M").astype(str)
bmap=dict(zip(bench.ym,bench.BM_Ret))   # forward BM per signal ym
L(f"[data] canonical panel H={H} T={T} ({months[0]}..{months[-1]}) | median N={int(panel.groupby('ym').size().median())}")

# Z_std (월별 횡단 demean+표준화)
Xraw=panel[FCOLS].values.astype(float); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1.0; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z)
F1=panel.F1.values.astype(float)
# managed 팩터수익 (eq.4): 신호월 k, 수익 k+1 실현
mfr=np.full((T,H),np.nan)
for k,t in enumerate(months):
    m=ymv==t; r=F1[m]; ok=np.isfinite(r)
    if ok.sum()<25: continue
    mfr[k]=(Z[m][ok].T@r[ok])/ok.sum()
mkt_all=np.array([bmap.get(mm,np.nan) for mm in months])

def orth_mkt(Fm,mk):
    ok=np.isfinite(mk);
    if ok.sum()<10: return Fm.copy()
    mk2=mk.copy(); mk2[~ok]=np.nanmean(mk[ok]); mkc=mk2-mk2.mean(); den=mkc@mkc
    if den<1e-12: return Fm.copy()
    beta=(Fm-Fm.mean(0)).T@mkc/den
    return Fm-np.outer(mkc,beta)
def moments(Fm):
    mu=Fm.mean(0); C=(Fm-mu).T@(Fm-mu)/Fm.shape[0]; return mu,C
def r2_oos(mu2,C2,b): e=mu2-C2@b; return 1.0-(e@e)/(mu2@mu2)
def cv_gamma(Fm,gs,K=3):
    rng=np.random.RandomState(0); idx=rng.permutation(Fm.shape[0]); folds=np.array_split(idx,K)
    best=-1e18; bg=gs[-1]
    for g in gs:
        acc=[]
        for f in range(K):
            te=folds[f]; tr=np.concatenate([folds[j] for j in range(K) if j!=f])
            mu_tr,C_tr=moments(Fm[tr]); mu_te,C_te=moments(Fm[te])
            acc.append(r2_oos(mu_te,C_te,np.linalg.solve(C_tr+g*np.eye(H),mu_tr)))
        a=np.mean(acc)
        if a>best: best=a; bg=g
    return bg,best
def cv_kpc(Fm,gsmall,ks,K=3):
    rng=np.random.RandomState(1); idx=rng.permutation(Fm.shape[0]); folds=np.array_split(idx,K)
    # fold별 eigh 1회만 (k 전체 재사용)
    fold=[]
    for f in range(K):
        te=folds[f]; tr=np.concatenate([folds[j] for j in range(K) if j!=f])
        mu_tr,C_tr=moments(Fm[tr]); mu_te,C_te=moments(Fm[te])
        d,Q=np.linalg.eigh(C_tr); d=d[::-1]; Q=Q[:,::-1]
        fold.append((mu_tr,mu_te,C_te,d,Q))
    best=-1e18; bk=ks[0]
    for k in ks:
        acc=[]
        for (mu_tr,mu_te,C_te,d,Q) in fold:
            Qk=Q[:,:k]; dk=np.where(d[:k]>1e-12,d[:k],1e-12)
            acc.append(r2_oos(mu_te,C_te,Qk@((Qk.T@mu_tr)/(dk+gsmall))))
        a=np.mean(acc)
        if a>best: best=a; bk=k
    return bk,best

# ── Phase A: full-sample 복제 요약 (canonical) ──
kk_all=[k for k in range(T) if np.isfinite(mfr[k]).all()]
Fo=orth_mkt(mfr[kk_all],mkt_all[kk_all]); mu,C=moments(Fo); tau=np.trace(C)
gs=np.logspace(-4,5,80)*(tau/H)
gstar,cvg=cv_gamma(Fo,gs); kstar,cvk=cv_kpc(Fo,gstar,[1,2,3,5,8,12,20,40])
bL2f=np.linalg.solve(C+gstar*np.eye(H),mu); sr2=mu@bL2f
kappa=np.sqrt(tau/(gstar*Fo.shape[0]))
print(f"\n[Phase A full-sample, canonical] T_managed={len(kk_all)} | γ*={gstar:.3e}(γ*/mean_eig={gstar/(tau/H):.1f}) κ={kappa:.3f}")
print(f"  CV R²_oos L2={cvg:+.4f} | PC-sparse best k={kstar} R²={cvk:+.4f} | 함의 monthly maxSR²={sr2:.4f}(annualSR≈{np.sqrt(max(sr2,0)*12):.2f})")

# ── Phase B: PIT 확장윈도우 (연간 CV refit) → L2 + PC-sparse 스코어 ──
min_hist=60; refit=12
gsB=np.logspace(-4,5,60)
rows_l2=[]; rows_pc=[]; diag=[]; cur_g=None; cur_k=None
def ym2date(ym): return pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0)
for m in range(min_hist,T):
    mm=months[m]
    if (m-min_hist)%24==0: L(f"  [PhaseB] {mm} ({m-min_hist+1}/{T-min_hist})")
    kk=[k for k in range(m) if np.isfinite(mfr[k]).all()]   # 수익 실현 ≤ m월 (PIT)
    if len(kk)<min_hist: continue
    Fm=mfr[kk]; Fo=orth_mkt(Fm,mkt_all[kk]); mu_,C_=moments(Fo); tau_=np.trace(C_)
    if (m-min_hist)%refit==0 or cur_g is None:
        cur_g,cg=cv_gamma(Fo,gsB*(tau_/H)); cur_k,ck=cv_kpc(Fo,cur_g,[1,2,3,5,8,12,20,40])
        diag.append((mm,cur_g,tau_/H,cur_k,cg,ck))
    bL2=np.linalg.solve(C_+cur_g*np.eye(H),mu_)
    d,Q=np.linalg.eigh(C_); d=d[::-1]; Q=Q[:,::-1]; Qk=Q[:,:cur_k]; dk=np.where(d[:cur_k]>1e-12,d[:cur_k],1e-12)
    bPC=Qk@((Qk.T@mu_)/(dk+cur_g))
    msk=ymv==mm; zt=Z[msk]; tks=tkv[msk]; dt=ym2date(mm)
    for tk,a,b in zip(tks,zt@bL2,zt@bPC):
        rows_l2.append((dt,tk,a)); rows_pc.append((dt,tk,b))
dL2=pd.DataFrame(rows_l2,columns=["Date","Ticker","score"]); dPC=pd.DataFrame(rows_pc,columns=["Date","Ticker","score"])
dL2.to_parquet(OUT+"/kns_scores_L2_canon.parquet",index=False); dPC.to_parquet(OUT+"/kns_scores_PCsparse_canon.parquet",index=False)
dg=pd.DataFrame(diag,columns=["refit","gamma","mean_eig","k_pc","cv_L2","cv_PC"])
print(f"\n[Phase B PIT] 결정월 {dL2.Date.nunique()} ({dL2.Date.min().date()}..{dL2.Date.max().date()}) 종목-월 {len(dL2)}")
print("[refit 연간]"); print(dg.assign(g_eig=(dg.gamma/dg.mean_eig).round(1)).round(4)[["refit","g_eig","k_pc","cv_L2","cv_PC"]].to_string(index=False))
# PIT IC 진단
ymd={months[k]:ym2date(months[k]) for k in range(T)}
for tag,dd in [("L2",dL2),("PCsparse",dPC)]:
    ics=[]
    dd2=dd.copy(); dd2["ym"]=pd.to_datetime(dd2.Date).dt.to_period("M").astype(str)
    for ym,g in dd2.groupby("ym"):
        msk=ymv==ym; y=pd.Series(F1[msk],index=tkv[msk]); s=g.set_index("Ticker")["score"]
        c=pd.concat([s,y],axis=1).dropna()
        if len(c)>25 and c.iloc[:,0].std()>1e-9: ics.append(np.corrcoef(c.iloc[:,0],c.iloc[:,1])[0,1])
    ics=np.array(ics); print(f"[PIT IC {tag}] mean={ics.mean():+.4f} ICIR={ics.mean()/ics.std()*np.sqrt(12):+.2f} n={len(ics)}")
print("saved kns_scores_L2_canon + kns_scores_PCsparse_canon.parquet")
