"""run_kns_phaseB.py — KNS 충실 구현 Phase B: PIT 확장윈도우 배포 슈퍼팩터 + PC-sparse 변형.
Phase A(full-sample 복제) 후속. 여기서는 C1(rolling/expanding only) 준수 배포용.

절차(월별 결정 m, ≥min_hist):
  1. 관측된 managed 팩터수익 mfr[0..m-1] (m월까지 실현) → 시장직교화(창 내) → μ̄,Σ (eq.13-14)
  2. γ*: 연 1회(refit=12) 3-fold CV(eq.30) 재선택, 그 사이 캐리. 확장 γ 그리드.
  3-A. L2 슈퍼팩터: b̂=(Σ+γ*I)⁻¹μ̄ (eq.22) → 종목점수 s_i=Z_std[i,m]·b̂
  3-B. PC-sparse (KNS §3.2/4 헤드라인): 상위 k PC만 사용한 sparse SDF.
       CV로 k 선택. b̂_PC = Q_k (D_k+γI)⁻¹ Q_k' μ̄. (few high-variance PCs)
저장: scores_dt(Date,Ticker,score) parquet — L2 및 PCsparse 각각. C단계 R 계약백테 소비.
"""
import os, sys, numpy as np, pandas as pd
os.environ.setdefault("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0,"02_Infrastructure/discovery")
from discovery_explore import ensure_panel, bm_fwd_map, load_families, nw_t, HORIZONS_ALL
R=os.environ["QM_ROOT"]; OUT=R+"/04_Research/factor_rotation/fof_first_slice"

panel=ensure_panel()
excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
fcols=[c for c in panel.columns if c not in excl]
months=sorted(panel["ym"].unique()); mi={m:i for i,m in enumerate(months)}; bmf=bm_fwd_map()
ymv=panel["ym"].values; tkv=panel["Ticker"].values; H=len(fcols); T=len(months)

# Z_std (월별 횡단 demean+표준화)
Xraw=panel[fcols].values.astype(float); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1.0; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z)
F1=panel["F1"].values.astype(float)
# managed 팩터수익 (신호월 k, 수익 k+1 실현)
mfr=np.full((T,H),np.nan)
for k,t in enumerate(months):
    m=ymv==t; r=F1[m]; ok=np.isfinite(r)
    if ok.sum()<25: continue
    mfr[k]=(Z[m][ok].T@r[ok])/ok.sum()
mkt_all=np.array([bmf(mm,1) for mm in months])

def orth_mkt(Fm,mk):
    mkc=mk-mk.mean(); den=mkc@mkc
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
            b=np.linalg.solve(C_tr+g*np.eye(H),mu_tr); acc.append(r2_oos(mu_te,C_te,b))
        a=np.mean(acc)
        if a>best: best=a; bg=g
    return bg,best
def cv_kpc(Fm,gsmall,ks,K=3):
    """PC-sparse: 상위 k PC만. CV로 k(+작은 ridge) 선택."""
    rng=np.random.RandomState(1); idx=rng.permutation(Fm.shape[0]); folds=np.array_split(idx,K)
    best=-1e18; bk=ks[0]
    for k in ks:
        acc=[]
        for f in range(K):
            te=folds[f]; tr=np.concatenate([folds[j] for j in range(K) if j!=f])
            mu_tr,C_tr=moments(Fm[tr]); mu_te,C_te=moments(Fm[te])
            d,Q=np.linalg.eigh(C_tr); d=d[::-1]; Q=Q[:,::-1]
            Qk=Q[:,:k]; dk=d[:k]; dk=np.where(dk>1e-12,dk,1e-12)
            b=Qk@((Qk.T@mu_tr)/(dk+gsmall))
            acc.append(r2_oos(mu_te,C_te,b))
        a=np.mean(acc)
        if a>best: best=a; bk=k
    return bk,best

min_hist=60; refit=12
gs=np.logspace(-4,5,80)   # 확장 γ 그리드 (경계확인)
ks=[1,2,3,5,8,12,20,40]
rows_l2=[]; rows_pc=[]; diag=[]
cur_g=None; cur_k=None
for m in range(min_hist,T):
    mm=months[m]
    # ≤ m-1 신호월의 managed 수익만(모두 m월까지 실현) — PIT
    kk=[k for k in range(m) if np.isfinite(mfr[k]).all()]
    if len(kk)<min_hist: continue
    Fm=mfr[kk]; mk=mkt_all[kk]; Fo=orth_mkt(Fm,mk)
    mu,C=moments(Fo)
    if (m-min_hist)%refit==0 or cur_g is None:
        cur_g,cvg=cv_gamma(Fo,gs*(np.trace(C)/H))
        cur_k,cvk=cv_kpc(Fo,cur_g,ks)
        diag.append((mm,cur_g,np.trace(C)/H,cur_k,cvg,cvk))
    bL2=np.linalg.solve(C+cur_g*np.eye(H),mu)
    d,Q=np.linalg.eigh(C); d=d[::-1]; Q=Q[:,::-1]; Qk=Q[:,:cur_k]; dk=np.where(d[:cur_k]>1e-12,d[:cur_k],1e-12)
    bPC=Qk@((Qk.T@mu)/(dk+cur_g))
    msk=ymv==mm; zt=Z[msk]; tks=tkv[msk]
    sL2=zt@bL2; sPC=zt@bPC
    dt=pd.Timestamp(mm+"-01")+pd.offsets.MonthEnd(0)
    for tk,a,b in zip(tks,sL2,sPC):
        rows_l2.append((dt,tk,a)); rows_pc.append((dt,tk,b))
dL2=pd.DataFrame(rows_l2,columns=["Date","Ticker","score"])
dPC=pd.DataFrame(rows_pc,columns=["Date","Ticker","score"])
dL2.to_parquet(OUT+"/kns_scores_L2.parquet",index=False)
dPC.to_parquet(OUT+"/kns_scores_PCsparse.parquet",index=False)
dg=pd.DataFrame(diag,columns=["refit_month","gamma","mean_eig","k_pc","cv_r2_L2","cv_r2_PC"])
dg.to_csv(OUT+"/kns_phaseB_refit.csv",index=False)
print(f"[PhaseB] 결정월 {dL2.Date.nunique()} ({dL2.Date.min().date()}..{dL2.Date.max().date()}) | 종목-월 {len(dL2)}")
print(f"[refit] {len(dg)}회 연간 재적합:")
print(dg.assign(g_over_eig=(dg.gamma/dg.mean_eig).round(1)).round(4)[["refit_month","g_over_eig","k_pc","cv_r2_L2","cv_r2_PC"]].to_string(index=False))
# 빠른 IC 진단 (PIT 점수)
for tag,dd in [("L2",dL2),("PCsparse",dPC)]:
    j=dd.merge(pd.DataFrame({"Date":[pd.Timestamp(months[k]+"-01")+pd.offsets.MonthEnd(0) for k in range(T)],
                             "ym":months}),on="Date")
    ics=[]
    for _,g in j.groupby("Date"):
        ym=g["ym"].iloc[0]; msk=ymv==ym; y=pd.Series(F1[msk],index=tkv[msk])
        s=g.set_index("Ticker")["score"]; c=pd.concat([s,y],axis=1).dropna()
        if len(c)>25 and c.iloc[:,0].std()>1e-9: ics.append(np.corrcoef(c.iloc[:,0],c.iloc[:,1])[0,1])
    ics=np.array(ics); print(f"[PIT IC {tag}] mean={ics.mean():+.4f} ICIR={ics.mean()/ics.std()*np.sqrt(12):+.2f} n={len(ics)}")
print("saved kns_scores_L2.parquet + kns_scores_PCsparse.parquet")
