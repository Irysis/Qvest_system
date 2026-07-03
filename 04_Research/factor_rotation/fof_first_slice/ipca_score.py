"""ipca_score.py MODE K — Kelly-Pruitt-Su (2019) "Characteristics Are Covariances" IPCA 충실 구현.
restricted 모델(Γ_α=0): rᵢ,ₜ₊₁ = βᵢ,ₜ fₜ₊₁ + ε, 시변 loading βᵢ,ₜ=zᵢ,ₜ'Γ (특성=loading instrument).
managed portfolio: xₜ=Zₜ'rₜ₊₁ (L,), Wₜ=Zₜ'Zₜ (L,L). ALS:
  factor:  fₜ = (Γ'WₜΓ)⁻¹ Γ'xₜ
  gamma:   vec(Γ) = [Σₜ(fₜfₜ')⊗Wₜ]⁻¹ vec(Σₜ xₜfₜ')   (블록조립 효율화: 블록(j,k)=Σₜ f_tj f_tk Wₜ)
슈퍼팩터 종목점수 = 조건부 기대수익 sᵢ = zᵢ,ₜ'Γ̂ λ̂  (λ=(1/T)Σfₜ). 벡터형 v=Γλ (rotation-invariant).
PIT 확장윈도우(연간 refit, ≤m 실현수익만). Z = master 327 특성 월별 횡단표준화 + 상수열. long-only top-25는 R 계약.
"""
import os, sys, numpy as np, pandas as pd
def Lg(*a): print(*a,flush=True)
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; os.environ.setdefault("QM_ROOT",R)
sys.path.insert(0,R+"/02_Infrastructure/discovery")
from discovery_explore import ensure_panel, HORIZONS_ALL
OUT=R+"/04_Research/factor_rotation/fof_first_slice"
MODE=sys.argv[1] if len(sys.argv)>1 else "allclean"
KS=[int(x) for x in (sys.argv[2].split(",") if len(sys.argv)>2 else ["1","4","6"])]
_p=ensure_panel(); excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
FCOLS=[c for c in _p.columns if c not in excl]; H=len(FCOLS)

M=pd.read_parquet(OUT+"/kns_master_panel.parquet")
if MODE=="canonical": mask=(M.K200f|M.KQ150f)
elif MODE=="allclean": mask=(M.nret>=15)&(~M.bad)
elif MODE=="allliq": mask=(M.nret>=15)&(~M.bad)&(M.adv>=2e8)
else: raise SystemExit("MODE?")
panel=M[mask].copy(); months=sorted(panel.ym.unique()); T=len(months)
ymv=panel.ym.values; tkv=panel.Ticker.values; F1=panel.F1.values.astype(float)
Lg(f"[IPCA {MODE}] rows {len(panel)} T={T} median N {int(panel.groupby('ym').size().median())} L={H}(+const)")
# Z_std (월별 횡단 표준화) + 상수열
Xraw=panel[FCOLS].values.astype(float); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1.0; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z)
L=H+1  # + 상수
# managed 적률 precompute: x[t] (L,), W[t] (L,L)  — 신호월 t, 수익 t+1 실현
X=np.full((T,L),np.nan); W=np.zeros((T,L,L)); valid=np.zeros(T,bool)
for k,t in enumerate(months):
    m=ymv==t; r=F1[m]; ok=np.isfinite(r)
    if ok.sum()<25: continue
    z=np.column_stack([np.ones(ok.sum()), Z[m][ok]])   # [const, chars]  (Nk, L)
    rr=r[ok]
    X[k]=z.T@rr; W[k]=z.T@z; valid[k]=True
Lg(f"[IPCA {MODE}] managed 적률 준비 valid months {valid.sum()}")

def ipca_als(idx, K, iters=25, tol=1e-6):
    Xi=X[idx]; Wi=W[idx]; Tw=len(idx)
    # init Γ: SVD of managed returns X (L×Tw) top-K
    U,S,_=np.linalg.svd(Xi.T, full_matrices=False)  # Xi is Tw×L → svd → top-K right-vecs
    G=np.linalg.svd(Xi, full_matrices=False)[2][:K].T  # L×K (top-K right singular vecs of Tw×L)
    Fmat=np.zeros((Tw,K)); prev=None
    for it in range(iters):
        # factor step
        for a in range(Tw):
            GWG=G.T@Wi[a]@G; Fmat[a]=np.linalg.solve(GWG+1e-10*np.eye(K), G.T@Xi[a])
        # gamma step: 블록(j,k)=Σ_a f_aj f_ak W_a ; A (LK×LK), b=vec(Σ_a x_a f_a')
        A=np.zeros((L*K,L*K))
        for j in range(K):
            for kk in range(j,K):
                blk=np.einsum('a,aij->ij', Fmat[:,j]*Fmat[:,kk], Wi)  # L×L
                A[j*L:(j+1)*L, kk*L:(kk+1)*L]=blk
                if kk!=j: A[kk*L:(kk+1)*L, j*L:(j+1)*L]=blk
        b=(Xi[:,:,None]*Fmat[:,None,:]).sum(0)  # L×K = Σ_a x_a f_a'
        rg=1e-4*np.mean(np.abs(np.diag(A)))+1e-10  # 상대 ridge (L=327≫N 고차원 안정화)
        gv=np.linalg.solve(A+rg*np.eye(L*K), b.reshape(-1,order='F'))
        G=gv.reshape(L,K,order='F')
        # 정규화: Γ'Γ=I (수치안정), F 회전
        Gq,Rq=np.linalg.qr(G); G=Gq; Fmat=Fmat@Rq.T
        v=G@Fmat.mean(0)  # 수렴판정용 슈퍼팩터 벡터 (rotation-invariant)
        if prev is not None and np.max(np.abs(v-prev))<tol: break
        prev=v
    lam=Fmat.mean(0)
    return G@lam  # 슈퍼팩터 벡터 v=Γλ (L,)

min_hist=60; refit=12
def ym2date(ym): return pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0)
best_ic=-9; best_K=None; best_scores=None
for K in KS:
    rows=[]; curv=None
    for m in range(min_hist,T):
        mm=months[m]
        idx=np.array([k for k in range(m) if valid[k]])  # ≤m-1 실현 (PIT)
        if len(idx)<min_hist: continue
        if (m-min_hist)%refit==0 or curv is None:
            curv=ipca_als(idx, K)
        ms=ymv==mm; zt=np.column_stack([np.ones(ms.sum()), Z[ms]])  # (Nm, L)
        s=zt@curv
        for tk,a in zip(tkv[ms],s): rows.append((ym2date(mm),tk,a))
    d=pd.DataFrame(rows,columns=["Date","Ticker","score"])
    # PIT IC
    d2=d.copy(); d2["ym"]=pd.to_datetime(d2.Date).dt.to_period("M").astype(str); ics=[]
    for ym,g in d2.groupby("ym"):
        ms=ymv==ym; y=pd.Series(F1[ms],index=tkv[ms]); c=pd.concat([g.set_index("Ticker")["score"],y],axis=1).dropna()
        if len(c)>25 and c.iloc[:,0].std()>1e-9: ics.append(np.corrcoef(c.iloc[:,0],c.iloc[:,1])[0,1])
    ics=np.array(ics); icir=ics.mean()/ics.std()*np.sqrt(12)
    Lg(f"[IPCA {MODE} K={K}] PIT IC mean={ics.mean():+.4f} ICIR={icir:+.2f} n={len(ics)} 결정월 {d.Date.nunique()}")
    d.to_parquet(OUT+f"/scores_IPCA_{MODE}_K{K}.parquet",index=False)
    if icir>best_ic: best_ic=icir; best_K=K; best_scores=f"scores_IPCA_{MODE}_K{K}.parquet"
Lg(f"[IPCA {MODE}] ★best K={best_K} ICIR={best_ic:+.2f} → {best_scores}")
