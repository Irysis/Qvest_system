"""build_ipca_ridge.py — 구조적-선형 개념고도화: 다변량 ridge + 저계수 PCA-ridge (IPCA 사촌).
marginal-IC 가중(base) 대비 '다변량 구조 통제'가 이득인지 (FWL-직교라 붕괴 예상 — 실측 확인).
expanding-window annual refit, IS-only PIT. score = Z@coef → CSV → 동일 R evalS로 base 비교.
"""
import os, numpy as np, pandas as pd, pyarrow.parquet as pq
from sklearn.linear_model import Ridge
from sklearn.decomposition import PCA
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
ps=pd.read_parquet(R+"/outputs/ramp/pure_factor_scores.parquet",columns=["signal_date","security_id","factor_id","neutralized_z"])
ps["ym"]=pd.to_datetime(ps["signal_date"]).dt.strftime("%Y-%m")
Wd=ps.pivot_table(index=["ym","security_id"],columns="factor_id",values="neutralized_z").fillna(0.0)
chars=list(Wd.columns); print("wide chars:",len(chars),"rows:",len(Wd))
# 월간 forward return (RAWDATA)
rd=pq.read_table(R+"/.cache/RAWDATA.parquet",columns=["Date","Ticker","Ret"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd=rd.dropna(subset=["Ret"])
mr=rd.groupby(["Ticker","ym"])["Ret"].apply(lambda r:np.expm1(np.log1p(r.clip(-0.99)).sum())).reset_index()
mr=mr.sort_values(["Ticker","ym"]); mr["fwd"]=mr.groupby("Ticker")["Ret"].shift(-1)
D=Wd.reset_index().merge(mr[["Ticker","ym","fwd"]].rename(columns={"Ticker":"security_id"}),on=["ym","security_id"],how="left")
months=sorted(D["ym"].unique()); mi={m:i for i,m in enumerate(months)}
X=D[chars].values; y=D["fwd"].values; ym=D["ym"].values
# per-month cross-sectional z of y (rank-ish target)
def cszscore(y,ym):
    o=np.full(len(y),np.nan);
    for t in np.unique(ym):
        m=ym==t; v=y[m]; s=np.nanstd(v)
        o[m]=(v-np.nanmean(v))/(s if s>0 else 1)
    return o
yz=cszscore(y,ym)
pred_r=np.full(len(D),np.nan); pred_p=np.full(len(D),np.nan)
OOS=months[60:]; rid=None; pcar=None; pca=None
for i,t in enumerate(OOS):
    if i%12==0:   # annual refit, IS-only
        tr=(np.array([mi[m] for m in ym])<mi[t]) & np.isfinite(yz)
        rid=Ridge(alpha=200).fit(X[tr],yz[tr])
        pca=PCA(n_components=20).fit(X[tr]); pcar=Ridge(alpha=20).fit(pca.transform(X[tr]),yz[tr])
    m=ym==t
    if m.sum():
        pred_r[m]=rid.predict(X[m]); pred_p[m]=pcar.predict(pca.transform(X[m]))
D["score_ridge"]=pred_r; D["score_pcar"]=pred_p
out=D.loc[D["score_ridge"].notna(),["ym","security_id","score_ridge","score_pcar"]].rename(columns={"security_id":"tic"})
out.to_csv(OUT+"/ipca_scores.csv",index=False)
print("saved ipca_scores.csv rows:",len(out),"| score_ridge vs base 상관은 R eval에서")
