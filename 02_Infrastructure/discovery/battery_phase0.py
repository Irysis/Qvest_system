# Phase 0 방법론 배터리 Round 1 (도훈 mandate: 다방법론 동시 실측, 실패=다음 입력)
#   Phase 0 실패모드 공략: ①최근 감쇠 → rolling/recency/regime-cond  ②seed 취약 → 결정적 선형/bagged/앙상블
#   판정: 최근(2021-26) 순 active IR (감쇠 돌파) + 전기간. net top25 long-only.
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings("ignore")
from sklearn.linear_model import Ridge, ElasticNet
from sklearn.neural_network import MLPRegressor
from sklearn.ensemble import HistGradientBoostingRegressor as HGB
from sklearn.preprocessing import StandardScaler
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
df=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in df.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]
df[fcols]=df[fcols].fillna(0.0); df=df.dropna(subset=["fwd_ret_1m","score_eff"]).reset_index(drop=True)
df["y"]=df.groupby("ym")["fwd_ret_1m"].transform(lambda s:(s-s.mean())/(s.std()+1e-9))
months=sorted(df["ym"].unique()); OOS=months[60:]
midx={m:i for i,m in enumerate(months)}
# bm 월간(현재/forward) + regime(trailing12m mkt sign)
bm=pd.read_parquet(CACHE+"/benchmark.parquet"); bc=[c for c in ("BM_Ret","Ret","bm_ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmm=bm.groupby("ym")[bc].apply(lambda r:np.expm1(np.log1p(r).sum())).sort_index()
bmfwd=bmm.shift(-1); df["bm_fwd"]=df["ym"].map(bmfwd)
reg=(bmm.rolling(12).sum()>0).map({True:"BULL",False:"BEAR"}); regmap=reg.to_dict()
df["regime"]=df["ym"].map(regmap).fillna("BULL")

Xall=df[["score_eff"]+fcols].values; yall=df["y"].values; ymarr=df["ym"].values; regarr=df["regime"].values
def fit_pred(spec, Xtr, ytr, Xte, w=None):
    kind=spec["kind"]
    if kind=="ridge": m=Ridge(alpha=spec.get("alpha",300.0))
    elif kind=="enet": m=ElasticNet(alpha=spec.get("alpha",0.01),l1_ratio=0.5,max_iter=2000)
    elif kind=="mlp": m=MLPRegressor(hidden_layer_sizes=(32,),alpha=1.0,max_iter=200,random_state=spec.get("seed",0))
    elif kind=="hgb":
        preds=[]
        for s in spec.get("seeds",[42]):
            mm=HGB(max_iter=300,learning_rate=0.03,max_leaf_nodes=15,max_depth=4,min_samples_leaf=80,
                   l2_regularization=5.0,max_features=0.6,early_stopping=False,random_state=s)
            mm.fit(Xtr,ytr,sample_weight=w); preds.append(mm.predict(Xte))
        return np.mean(preds,axis=0)
    if kind in("ridge","enet","mlp"):
        sc=StandardScaler().fit(Xtr); Xtr2=sc.transform(Xtr); Xte2=sc.transform(Xte)
        m.fit(Xtr2,ytr,sample_weight=w) if kind!="mlp" else m.fit(Xtr2,ytr)
        return m.predict(Xte2)

def run_method(spec, window=None, recency_hl=None, regime_cond=False, retrain=6):
    pred=np.full(len(df),np.nan); m=None; cache={}
    for i,ym in enumerate(OOS):
        if i%retrain==0:
            tr_mask = ymarr<ym
            if window: tr_mask = tr_mask & (np.array([midx[x] for x in ymarr])>=midx[ym]-window)
            w=None
            if recency_hl:
                age=np.array([midx[ym]-midx[x] for x in ymarr]); w=np.where(tr_mask,0.5**(age/recency_hl),0.0)[tr_mask]
            cache={"trmask":tr_mask,"w":w}
        tr_mask=cache["trmask"]; w=cache["w"]; te_mask=ymarr==ym
        if regime_cond:
            p=np.zeros(te_mask.sum())
            for rg in ("BULL","BEAR"):
                trm=tr_mask&(regarr==rg); tem=te_mask&(regarr==rg)
                if trm.sum()<500 or tem.sum()==0:
                    trm=tr_mask; # fallback 전체
                if tem.sum()>0:
                    ww=w[ (regarr==rg)[tr_mask] ] if w is not None and (regarr[tr_mask]==rg).any() else None
                    pr=fit_pred(spec,Xall[trm],yall[trm],Xall[tem],None)
                    pred[np.where(te_mask)[0][ (regarr[te_mask]==rg) ]]=pr
        else:
            pred[te_mask]=fit_pred(spec,Xall[tr_mask],yall[tr_mask],Xall[te_mask], w)
    return pred

_tk=df["Ticker"].values; _fwd=df["fwd_ret_1m"].values; _bmf=df["bm_fwd"].values; _oos=set(OOS)
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
def ir_period(ser,lo=None,hi=None):
    r=ser if lo is None else ser[(ser["ym"]>=lo)&(ser["ym"]<=hi)]
    if len(r)<7: return np.nan
    act=r["net"].values-r["bm"].values; return act.mean()/act.std()*np.sqrt(12)

OUTF=OUT+"/battery_round1_results.txt"
open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")
log("=== Battery Round 1 — 다방법론 (감쇠+seed 공략). 핵심열=21-26(감쇠돌파) ===")
log(f"{'method':28s} {'full':>7} {'10-15':>7} {'16-20':>7} {'21-26':>7}")

methods=[
 ("score_eff(base)", df["score_eff"].values),
 # 선형(결정적 — seed 무관) × decay
 ("Ridge exp",          dict(spec=dict(kind="ridge"),retrain=6)),
 ("Ridge roll60",       dict(spec=dict(kind="ridge"),window=60,retrain=6)),
 ("Ridge roll36",       dict(spec=dict(kind="ridge"),window=36,retrain=6)),
 ("Ridge recency36",    dict(spec=dict(kind="ridge"),recency_hl=36,retrain=6)),
 ("Ridge recency18",    dict(spec=dict(kind="ridge"),recency_hl=18,retrain=6)),
 ("Ridge regime-cond",  dict(spec=dict(kind="ridge"),regime_cond=True,retrain=6)),
 ("ENet exp",           dict(spec=dict(kind="enet"),retrain=6)),
 ("ENet recency36",     dict(spec=dict(kind="enet"),recency_hl=36,retrain=6)),
 # HGB(bagged — seed 안정화) × decay
 ("HGB bag3 exp",       dict(spec=dict(kind="hgb",seeds=[42,1,7]),retrain=12)),
 ("HGB bag3 roll60",    dict(spec=dict(kind="hgb",seeds=[42,1,7]),window=60,retrain=12)),
 ("HGB bag3 recency36", dict(spec=dict(kind="hgb",seeds=[42,1,7]),recency_hl=36,retrain=12)),
 ("HGB bag2 regime",    dict(spec=dict(kind="hgb",seeds=[42,1]),regime_cond=True,retrain=12)),
 # MLP × decay
 ("MLP exp",            dict(spec=dict(kind="mlp",seed=0),retrain=12)),
 ("MLP recency36",      dict(spec=dict(kind="mlp",seed=0),recency_hl=36,retrain=12)),
]
store={}
for nm,m in methods:
    try:
        sig = m if isinstance(m,np.ndarray) else run_method(**m)
        store[nm]=sig; ser=net_series(sig)
        v=[ir_period(ser),ir_period(ser,"2010-01","2015-12"),ir_period(ser,"2016-01","2020-12"),ir_period(ser,"2021-01","2026-12")]
        log(f"{nm:28s} {v[0]:7.3f} {v[1]:7.3f} {v[2]:7.3f} {v[3]:7.3f}{' <-21-26+' if v[3]>0.3 else ''}")
    except Exception as e:
        log(f"{nm:28s} ERR {e}")

def rankavg(*names):
    zs=[]
    for n in names:
        a=store[n]; z=np.full(len(a),np.nan)
        for ym in OOS:
            idx=np.where((ymarr==ym)&~np.isnan(a))[0]
            if len(idx)>1: v=a[idx]; z[idx]=(v-v.mean())/(v.std()+1e-9)
        zs.append(z)
    return np.nanmean(np.vstack(zs),axis=0)
for combo,label in [(("Ridge exp","HGB bag3 exp"),"ENS Ridge+HGB exp"),
                    (("Ridge recency36","HGB bag3 recency36"),"ENS recency36"),
                    (("Ridge regime-cond","HGB bag2 regime"),"ENS regime")]:
    if all(c in store for c in combo):
        try:
            sig=rankavg(*combo); ser=net_series(sig)
            v=[ir_period(ser),ir_period(ser,"2010-01","2015-12"),ir_period(ser,"2016-01","2020-12"),ir_period(ser,"2021-01","2026-12")]
            log(f"{label:28s} {v[0]:7.3f} {v[1]:7.3f} {v[2]:7.3f} {v[3]:7.3f}{' <-21-26+' if v[3]>0.3 else ''}")
        except Exception as e: log(f"{label:28s} ERR {e}")
log("=== done ===")
