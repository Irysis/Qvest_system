# Phase 0 배터리 Round 2 — FEATURE 축 (Round1 교훈: 결합 무관 최근死, feature축 미탐색)
#   가설: 최근 알파가 327팩터 *부분집합*에 숨었고 전체set이 희석. recency-IC 동적 선택/가중으로 회수?
#   판정: 21-26(최근) 순 active IR. net top25 long-only. 시간 무제한(백그라운드).
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings("ignore")
from sklearn.linear_model import Ridge
from sklearn.ensemble import HistGradientBoostingRegressor as HGB
from sklearn.preprocessing import StandardScaler
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/battery_round2_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")

df=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in df.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]
df[fcols]=df[fcols].fillna(0.0); df=df.dropna(subset=["fwd_ret_1m","score_eff"]).reset_index(drop=True)
df["y"]=df.groupby("ym")["fwd_ret_1m"].transform(lambda s:(s-s.mean())/(s.std()+1e-9))
months=sorted(df["ym"].unique()); OOS=months[60:]; midx={m:i for i,m in enumerate(months)}
bm=pd.read_parquet(CACHE+"/benchmark.parquet"); bc=[c for c in ("BM_Ret","Ret","bm_ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmm=bm.groupby("ym")[bc].apply(lambda r:np.expm1(np.log1p(r).sum())).sort_index()
df["bm_fwd"]=df["ym"].map(bmm.shift(-1))
ymarr=df["ym"].values; _tk=df["Ticker"].values; _fwd=df["fwd_ret_1m"].values; _bmf=df["bm_fwd"].values; _oos=set(OOS)

# ---- 팩터별 월별 IC (PIT: 결정월 t의 trailing IC = 실현 ≤ t-1 의 last 36m 평균) ----
log("trailing-IC 계산 중...")
icm={}  # factor -> Series(ym -> IC)  (IC at month m = corr(factor[m], fwd[m]), realized m+1)
fr=df[["ym"]+fcols+["fwd_ret_1m"]]
for f in fcols:
    s=fr.groupby("ym").apply(lambda g: g[f].corr(g["fwd_ret_1m"],method="spearman"))
    icm[f]=s
IC=pd.DataFrame(icm)            # index ym, cols factors
IC=IC.reindex(months)
trail=IC.shift(1).rolling(36,min_periods=12).mean()   # shift1=PIT(실현지연), trailing36
# 결정월 t에서 쓸 trailing IC: trail.loc[t]

Fmat=df[fcols].values
def net_series(sigvals):
    msk=np.array([y in _oos for y in ymarr]) & ~np.isnan(sigvals) & ~np.isnan(_fwd)
    d=pd.DataFrame({"ym":ymarr[msk],"tk":_tk[msk],"fwd":_fwd[msk],"bm":_bmf[msk],"sig":sigvals[msk]})
    recs=[]; prev=set()
    for ym,g in d.groupby("ym",sort=True):
        sv=g["sig"].values; idx=np.argpartition(-sv,min(25,len(sv)-1))[:25]
        sel=set(g["tk"].values[idx]); gross=g["fwd"].values[idx].mean()
        to=2*(25-len(sel&prev))/25 if prev else 1.0
        recs.append((ym,gross-to*0.0015,g["bm"].iloc[0])); prev=sel
    return pd.DataFrame(recs,columns=["ym","net","bm"])
def ir(ser,lo=None,hi=None):
    r=ser if lo is None else ser[(ser["ym"]>=lo)&(ser["ym"]<=hi)]
    if len(r)<7: return np.nan
    a=r["net"].values-r["bm"].values; return a.mean()/a.std()*np.sqrt(12)
def report(nm,sig):
    s=net_series(sig); v=[ir(s),ir(s,"2010-01","2015-12"),ir(s,"2016-01","2020-12"),ir(s,"2021-01","2026-12")]
    log(f"{nm:30s} {v[0]:7.3f} {v[1]:7.3f} {v[2]:7.3f} {v[3]:7.3f}{' <-21-26+' if v[3]>0.3 else ''}")

log(f"{'method':30s} {'full':>7} {'10-15':>7} {'16-20':>7} {'21-26':>7}")
fidx={f:j for j,f in enumerate(fcols)}

# M1 동적 IC-가중 composite (감쇠팩터 자동 약화/flip, ML無)
def dyn_composite(topk=None, posonly=False):
    sig=np.full(len(df),np.nan)
    for ym in OOS:
        w=trail.loc[ym].values  # per-factor trailing IC
        w=np.nan_to_num(w)
        if posonly: w=np.where(w>0,w,0.0)
        if topk:
            thr=np.sort(np.abs(w))[::-1]; cut=thr[min(topk,len(thr)-1)]; w=np.where(np.abs(w)>=cut,w,0.0)
        te=np.where(ymarr==ym)[0]
        sig[te]=Fmat[te]@w
    return sig
report("M1 dyn-IC composite(all)", dyn_composite())
report("M2 dyn-IC composite top30", dyn_composite(topk=30))
report("M3 dyn-IC composite top60", dyn_composite(topk=60))
report("M4 dyn-IC pos-only top60", dyn_composite(topk=60,posonly=True))

# M5/M6 recency-IC 상위K 팩터 선택 후 ML (train도 그 부분집합)
yall=df["y"].values
def selK_ml(kind,topk=40,retrain=6):
    sig=np.full(len(df),np.nan); m=None; feats=None
    for i,ym in enumerate(OOS):
        if i%retrain==0:
            w=np.abs(np.nan_to_num(trail.loc[ym].values))
            feats=list(np.argsort(w)[::-1][:topk])
            tr=np.where((np.array([midx[x] for x in ymarr])<midx[ym]))[0]
            Xtr=Fmat[np.ix_(tr,feats)]; ytr=yall[tr]
            if kind=="ridge":
                sc=StandardScaler().fit(Xtr); m=Ridge(alpha=100.0).fit(sc.transform(Xtr),ytr); scaler=sc
            else:
                m=HGB(max_iter=300,learning_rate=0.03,max_leaf_nodes=15,max_depth=4,min_samples_leaf=80,
                      l2_regularization=5.0,random_state=42).fit(Xtr,ytr); scaler=None
        te=np.where(ymarr==ym)[0]; Xte=Fmat[np.ix_(te,feats)]
        sig[te]=m.predict(scaler.transform(Xte)) if scaler else m.predict(Xte)
    return sig
report("M5 selIC40 Ridge", selK_ml("ridge",40))
report("M6 selIC40 HGB", selK_ml("hgb",40))
report("M7 selIC20 HGB", selK_ml("hgb",20))

# M8 interaction: 최근IC 상위10 팩터 pairwise 곱 + 원본 → HGB
def inter_hgb(top=10,retrain=6):
    sig=np.full(len(df),np.nan); m=None; feats=None; pairs=None
    for i,ym in enumerate(OOS):
        if i%retrain==0:
            w=np.abs(np.nan_to_num(trail.loc[ym].values)); feats=list(np.argsort(w)[::-1][:top])
            pairs=[(a,b) for ai,a in enumerate(feats) for b in feats[ai+1:]]
            tr=np.where(np.array([midx[x] for x in ymarr])<midx[ym])[0]
            def build(rows):
                base=Fmat[np.ix_(rows,feats)]; itx=np.column_stack([Fmat[rows,a]*Fmat[rows,b] for a,b in pairs])
                return np.column_stack([base,itx])
            Xtr=build(tr); m=HGB(max_iter=300,learning_rate=0.03,max_leaf_nodes=15,max_depth=4,
                                 min_samples_leaf=80,l2_regularization=5.0,random_state=42).fit(Xtr,yall[tr])
            _build=build
        te=np.where(ymarr==ym)[0]; sig[te]=m.predict(_build(te))
    return sig
report("M8 interaction-top10 HGB", inter_hgb(10))
log("=== done ===")
