# Phase 0 #5 config 견고성 + #4용 base 시계열 산출
#   #5: HGB 설정 4종으로 walk-forward B → net top25 active IR/absSR (요행 아닌지)
#   산출: base_series.csv (OOS월: A_net, B_net, bm_fwd) → R #4 오버레이가 소비
import pandas as pd, numpy as np, os
from sklearn.ensemble import HistGradientBoostingRegressor as HGB
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
df=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in df.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]
df[fcols]=df[fcols].fillna(0.0); df=df.dropna(subset=["fwd_ret_1m","score_eff"]).reset_index(drop=True)
df["y"]=df.groupby("ym")["fwd_ret_1m"].transform(lambda s:(s-s.mean())/(s.std()+1e-9))
months=sorted(df["ym"].unique()); OOS=months[60:]; oos0=OOS[0]

# bm 월간 forward
bm=pd.read_parquet(CACHE+"/benchmark.parquet"); bc=[c for c in ("BM_Ret","Ret","bm_ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmm=bm.groupby("ym")[bc].apply(lambda r:np.expm1(np.log1p(r).sum())).sort_index()
bmfwd=bmm.shift(-1); df["bm_fwd"]=df["ym"].map(bmfwd)

def walkfwd(feats,cfg,retrain):
    pred=pd.Series(np.nan,index=df.index); m=None
    for i,ym in enumerate(OOS):
        if i%retrain==0: tr=df[df["ym"]<ym]; m=HGB(**cfg).fit(tr[feats].values,tr["y"].values)
        idx=df.index[df["ym"]==ym]; pred.loc[idx]=m.predict(df.loc[idx,feats].values)
    return pred

def net_series(sigvals):
    d=df.assign(sig=sigvals).dropna(subset=["sig"]); d=d[d["ym"].isin(OOS)]
    recs=[]; prev=set()
    for ym,g in d.groupby("ym"):
        g=g.sort_values("sig",ascending=False); sel=list(g["Ticker"].head(25))
        gross=g[g["Ticker"].isin(sel)]["fwd_ret_1m"].mean()
        allt=set(sel)|prev
        to=sum(abs((1/25 if t in sel else 0)-(1/len(prev) if t in prev else 0)) for t in allt) if prev else 1.0
        recs.append((ym,gross-to*0.0015,g["bm_fwd"].iloc[0])); prev=set(sel)
    return pd.DataFrame(recs,columns=["ym","net","bm"])

def metr(r):
    act=r["net"]-r["bm"]; return act.mean()/act.std()*np.sqrt(12), r["net"].mean()/r["net"].std()*np.sqrt(12)

base=dict(max_iter=300,learning_rate=0.03,max_leaf_nodes=15,max_depth=4,min_samples_leaf=80,
          l2_regularization=5.0,max_features=0.6,early_stopping=False,random_state=42)
configs={
 "cfg0 baseline(seed42)":      dict(base),
 "cfg1 leaves31/lr05/leaf50":  {**base,"max_leaf_nodes":31,"learning_rate":0.05,"min_samples_leaf":50,"l2_regularization":2.0,"random_state":1},
 "cfg2 leaves7/leaf120/l2_10": {**base,"max_leaf_nodes":7,"min_samples_leaf":120,"l2_regularization":10.0,"random_state":7},
 "cfg3 baseline(seed123)":     {**base,"random_state":123},
}
rA=net_series(df["score_eff"]); irA,srA=metr(rA)
print(f"#5 config 견고성 (net top25, OOS {oos0}~):  A score_eff  IR {irA:.3f}  absSR {srA:.3f}")
predB0=None
for k,(nm,cfg) in enumerate(configs.items()):
    rt=3 if k==0 else 6
    pB=walkfwd(["score_eff"]+fcols,cfg,rt); r=net_series(pB); ir,sr=metr(r)
    print(f"  {nm:30s} IR {ir:.3f}  absSR {sr:.3f}  ΔIR(B-A) {ir-irA:+.3f}")
    if k==0: predB0=pB; rB0=r

# #4용 base 시계열 emit (baseline cfg0)
out=rA.rename(columns={"net":"A_net"}).merge(rB0.rename(columns={"net":"B_net"})[["ym","B_net"]],on="ym")
out=out[["ym","A_net","B_net","bm"]]; out.to_csv(OUT+"/base_series.csv",index=False)
print("\nsaved base_series.csv (OOS",len(out),"월) → R #4 오버레이용")
