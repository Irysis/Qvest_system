"""proper_ipca.py — 결함4 수리: 진짜 IPCA(Kelly-Pruitt-Su joint ALS) + 튜닝된 ridge(alpha 그리드).
크루드 PCA-ridge("IPCA사촌")를 근거로 한 "구조적-선형 열위" 결론을 제대로 검증.
managed-portfolio ALS: x_t=Z_t'r_t, W_t=Z_t'Z_t. f_t=(Γ'W_tΓ)^-1 Γ'x_t; Γ = big-system solve. expanding refit.
score = Z Γ f̄ (IS-only) → CSV → 동일 R evalS. base=3.57.
"""
import os, numpy as np, pandas as pd, pyarrow.parquet as pq
from sklearn.linear_model import Ridge
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
ps=pd.read_parquet(R+"/outputs/ramp/pure_factor_scores.parquet",columns=["signal_date","security_id","factor_id","neutralized_z"])
ps["ym"]=pd.to_datetime(ps["signal_date"]).dt.strftime("%Y-%m")
Wd=ps.pivot_table(index=["ym","security_id"],columns="factor_id",values="neutralized_z").fillna(0.0)
chars=list(Wd.columns); L=len(chars)
rd=pq.read_table(R+"/.cache/RAWDATA.parquet",columns=["Date","Ticker","Ret"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd=rd.dropna(subset=["Ret"])
mr=rd.groupby(["Ticker","ym"])["Ret"].apply(lambda r:np.expm1(np.log1p(r.clip(-0.99)).sum())).reset_index()
mr=mr.sort_values(["Ticker","ym"]); mr["fwd"]=mr.groupby("Ticker")["Ret"].shift(-1)
D=Wd.reset_index().merge(mr[["Ticker","ym","fwd"]].rename(columns={"Ticker":"security_id"}),on=["ym","security_id"],how="left")
months=sorted(D["ym"].unique()); mi={m:i for i,m in enumerate(months)}
# per-month Z, r
bym={}
for t,g in D.groupby("ym"):
    Z=g[chars].values; r=g["fwd"].values; ok=np.isfinite(r)
    if ok.sum()>=25: bym[t]=(g["security_id"].values, Z, r, ok)
# precompute x_t, W_t (only for months with returns, for fitting)
XW={}
for t,(sid,Z,r,ok) in bym.items():
    Zt=Z[ok]; rt=r[ok]; n=len(rt)
    XW[t]=(Zt.T@rt/n, Zt.T@Zt/n)
def ipca_fit(train_months,K,n_iter=15):
    ts=[t for t in train_months if t in XW]
    xs=np.array([XW[t][0] for t in ts]); Ws=[XW[t][1] for t in ts]
    # init Γ: top-K eigvec of Σ x x'
    Sig=xs.T@xs/len(xs); ev,evec=np.linalg.eigh(Sig); G=evec[:,-K:]
    for it in range(n_iter):
        F=np.zeros((len(ts),K))
        for i,t in enumerate(ts):
            Wt=Ws[i]; A=G.T@Wt@G; F[i]=np.linalg.solve(A+1e-8*np.eye(K), G.T@xs[i])
        # Γ update: solve [Σ (f f') ⊗ (W W)] vecG = Σ vec(W x f')
        KL=K*L; Amat=np.zeros((KL,KL)); b=np.zeros(KL)
        for i,t in enumerate(ts):
            Wt=Ws[i]; ff=np.outer(F[i],F[i]); WW=Wt@Wt
            Amat+=np.kron(ff,WW); b+=np.reshape(Wt@np.outer(xs[i],F[i]),KL,order='F')
        vecG=np.linalg.solve(Amat+1e-6*np.eye(KL),b); G=vecG.reshape(L,K,order='F')
        # normalize
        G,_=np.linalg.qr(G)
    # f̄ = mean managed factor return
    F=np.zeros((len(ts),K))
    for i,t in enumerate(ts):
        A=G.T@Ws[i]@G; F[i]=np.linalg.solve(A+1e-8*np.eye(K),G.T@xs[i])
    return G, F.mean(0)
# expanding, refit every 24m, K grid
OOS=months[60:]
for K in (3,5):
    pred=np.full(len(D),np.nan); Gc=None; fbar=None
    for i,t in enumerate(OOS):
        if i%24==0:
            tr=[m for m in months if mi[m]<mi[t]]
            try: Gc,fbar=ipca_fit(tr,K)
            except Exception as e: print("fit fail",t,e)
        if Gc is not None and t in bym:
            sid,Z,r,ok=bym[t]; sc_=Z@(Gc@fbar)
            idx=D.index[D["ym"]==t]; pred[idx]=sc_
    D[f"ipca_K{K}"]=pred
# tuned ridge alpha grid
X=D[chars].values; y=D["fwd"].values; ym=D["ym"].values
yz=np.full(len(y),np.nan)
for t in np.unique(ym):
    m=ym==t; v=y[m]; s=np.nanstd(v); yz[m]=(v-np.nanmean(v))/(s if s>0 else 1)
for al in (20,100,500,2000):
    pr=np.full(len(D),np.nan); rid=None
    for i,t in enumerate(OOS):
        if i%12==0:
            tr=(np.array([mi[m] for m in ym])<mi[t])&np.isfinite(yz); rid=Ridge(alpha=al).fit(X[tr],yz[tr])
        m=ym==t
        if m.sum(): pr[m]=rid.predict(X[m])
    D[f"ridge_a{al}"]=pr
cols=["ipca_K3","ipca_K5","ridge_a20","ridge_a100","ridge_a500","ridge_a2000"]
out=D.loc[D[cols].notna().any(axis=1),["ym","security_id"]+cols].rename(columns={"security_id":"tic"})
out.to_csv(OUT+"/proper_ipca_scores.csv",index=False); print("saved proper_ipca_scores.csv",len(out),"cols:",cols)
