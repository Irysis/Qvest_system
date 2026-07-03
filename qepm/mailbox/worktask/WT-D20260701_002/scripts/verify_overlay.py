# 검증 Step1 — 후보(충실·결합) + 적대변형(plain-TS-mom·placebo·look-ahead) 시리즈 구성·export.
# R 계약경로(PerformanceAnalytics + oos + holdout)가 소비할 monthly CSV 생성.
import pandas as pd, numpy as np, pyarrow.parquet as pq, warnings
warnings.filterwarnings("ignore")
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
BT=ROOT+"/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results"
def log(s): print(s,flush=True)

dt=pd.read_csv(BT+"/period_returns_layer5.csv"); dt["anchor_date"]=pd.to_datetime(dt["anchor_date"])
dt=dt[np.isfinite(dt["ret_orig"])].sort_values("anchor_date").reset_index(drop=True); dt["ym"]=dt["realized_ym"].astype(str).str[:7]
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["Date"]=pd.to_datetime(bm["Date"]); bm=bm.dropna(subset=[bc]).sort_values("Date").reset_index(drop=True)
r=bm[bc].values; s=pd.Series(r); mu=s.rolling(252,min_periods=120).mean(); sd=s.rolling(252,min_periods=120).std()
rhat=np.clip(((s-mu)/(sd+1e-12)).values,-20,20); bm["ym"]=bm["Date"].dt.strftime("%Y-%m")
al=1-np.exp(-1/16); sig2=np.full(len(rhat),np.nan); acc=1.0
for t in range(len(rhat)):
    if np.isfinite(rhat[t]): acc=al*rhat[t]**2+(1-al)*acc; sig2[t]=acc
T=16; Nmax=6*T; nn=np.arange(Nmax+1); w=nn*np.exp(-2*nn/T); w=w/np.sqrt((w**2).sum()); phi=np.full(len(rhat),np.nan)
for t in range(Nmax,len(rhat)): phi[t]=np.clip(np.dot(w,rhat[t-Nmax:t+1][::-1]),-2.5,2.5)
bm["S_faith"]=0.13+0.79*sig2-0.17*phi+0.09*phi**2
# 적대①: plain-TS-momentum de-risk (추세 하락시 방어) — 논문 고유형태 없이
cum126=pd.Series(r).rolling(126,min_periods=80).sum().values   # 트레일링 6m 추세
bm["S_tsmom"]=-cum126    # 하락(음수)일수록 stress↑
# KOSPI 월간수익(벤치)
bmm=bm.groupby("ym").apply(lambda g:np.expm1(np.log1p(g[bc]).sum())).rename("bmret")
def lagmap(col):
    me=bm.groupby("ym")[col].last(); yms=sorted(me.index); nxt={yms[i]:yms[i+1] for i in range(len(yms)-1)}
    lag={nxt[k]:v for k,v in me.items() if k in nxt}; return dt["ym"].map(lag).values
dt["S_faith"]=lagmap("S_faith"); dt["S_tsmom"]=lagmap("S_tsmom")

bar=dt["beta_threshold_lag"].round(2); freq=bar.value_counts(normalize=True); lo=sorted([l for l in bar.unique() if l<0.999])
def exp_pct(x):
    o=np.full(len(x),np.nan)
    for i in range(len(x)):
        p=x[:i]; p=p[np.isfinite(p)]
        if len(p)>=24: o[i]=(p<x[i]).mean()
    return o
def build_beta(sig):
    pct=exp_pct(sig); cum=0.0; thr=[]
    for l in lo: f=freq.get(l,0); thr.append((l,1-cum-f,1-cum)); cum+=f
    def bp(p):
        if not np.isfinite(p): return 1.0
        for l,plo,ph in thr:
            if plo<=p<ph: return l
        return lo[0] if (lo and p>=1-cum) else 1.0
    return np.array([bp(p) for p in pct])
def ret_of(beta):
    db=np.abs(np.diff(np.r_[1.0,beta])); return dt["beta_R05_V5"].values*beta*dt["m4_weight_lag"].values*dt["ret_orig"].values - db*0.0015 - dt["db_R05_V5"].values*0.0015

bF=build_beta(dt["S_faith"].values); bT=build_beta(dt["S_tsmom"].values); bAR=dt["beta_threshold_lag"].values
bC=np.minimum(bAR,bF)
# 적대②: placebo — β_faithful 시간셔플(신호 타이밍 파괴, de-risk 강도만 유지)
rng=np.random.RandomState(42); bP=bF.copy(); rng.shuffle(bP)

out=pd.DataFrame({"ym":dt["ym"], "date":dt["anchor_date"],
  "ret_book":dt["ret_L5_V5"].values, "ret_faith":ret_of(bF), "ret_combine":ret_of(bC),
  "ret_tsmom":ret_of(bT), "ret_placebo":ret_of(bP)})
out["bmret"]=out["ym"].map(bmm)
out.to_csv(OUT+"/verify_overlay_series.csv",index=False)

def nwt(dd):
    dd=dd[np.isfinite(dd)]; n=len(dd); e=dd-dd.mean(); ss=(e@e)/n
    for l in range(1,4): ss+=2*(1-l/4)*((e[l:]@e[:-l])/n)
    return dd.mean()/np.sqrt(ss/n)
def sr(x): x=x[np.isfinite(x)]; return x.mean()/x.std()*np.sqrt(12)
log("=== Step1 python 요약 (파이썬 SR, 적대검증 방향) ===")
b=out["ret_book"].values
for cc,nm in [("ret_faith","충실"),("ret_combine","결합"),("ret_tsmom","★적대:plain-TS-mom"),("ret_placebo","★적대:placebo셔플")]:
    x=out[cc].values; log(f"  {nm:>18} SR {sr(x):.3f} | paired-t vs book {nwt(x-b):+.2f}")
log(f"  현 book SR {sr(b):.3f}")
log("  메커니즘 판독: 충실 > plain-TS-mom이면 paper-고유 / 비슷하면 generic 추세추종")
log("  placebo 판독: placebo paired-t≈0(엣지 소멸)이면 신호 타이밍이 real / placebo도 크게+이면 de-risk강도 아티팩트")
log(f"\n export → {OUT}/verify_overlay_series.csv (R 계약측정 소비)")
