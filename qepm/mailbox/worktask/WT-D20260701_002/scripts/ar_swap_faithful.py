# BOOK β_AR → 논문④ *충실* 예측변동성 오버레이 (e·ϕ 비대칭 포함). 앞 ϕ²-only 수정.
# 신호: 충실(논문계수 0.13+0.79σ²-0.17ϕ+0.09ϕ²) / KR-fit / trend-only(-0.17ϕ+0.09ϕ²) / ϕ²(구).
import pandas as pd, numpy as np, pyarrow.parquet as pq, warnings
warnings.filterwarnings("ignore")
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"
BT=ROOT+"/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results"
OUT=CACHE+"/discovery/ar_swap_faithful_results.txt"; open(OUT,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="utf-8") as f: f.write(s+"\n")

dt=pd.read_csv(BT+"/period_returns_layer5.csv"); dt["anchor_date"]=pd.to_datetime(dt["anchor_date"])
dt=dt[np.isfinite(dt["ret_orig"])].sort_values("anchor_date").reset_index(drop=True); dt["ym"]=dt["realized_ym"].astype(str).str[:7]
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["Date"]=pd.to_datetime(bm["Date"]); bm=bm.dropna(subset=[bc]).sort_values("Date").reset_index(drop=True)
r=bm[bc].values; s=pd.Series(r); mu=s.rolling(252,min_periods=120).mean(); sd=s.rolling(252,min_periods=120).std()
rhat=np.clip(((s-mu)/(sd+1e-12)).values,-20,20); bm["ym"]=bm["Date"].dt.strftime("%Y-%m")
# ϕ(T=16), σ²(EWMA 16)
T=16; Nmax=6*T; nn=np.arange(Nmax+1); w=nn*np.exp(-2*nn/T); w=w/np.sqrt((w**2).sum())
phi=np.full(len(rhat),np.nan)
for t in range(Nmax,len(rhat)): phi[t]=np.clip(np.dot(w,rhat[t-Nmax:t+1][::-1]),-2.5,2.5)
al=1-np.exp(-1/16); sig2=np.full(len(rhat),np.nan); acc=1.0
for t in range(len(rhat)):
    if np.isfinite(rhat[t]): acc=al*rhat[t]**2+(1-al)*acc; sig2[t]=acc
bm["phi"]=phi; bm["sig2"]=sig2
# 충실 예측변동성 (논문계수 equity e=-0.17) / KR-fit / trend-only / ϕ²
bm["S_faith"]=0.13+0.79*bm["sig2"]-0.17*bm["phi"]+0.09*bm["phi"]**2
bm["S_krfit"]=0.207+0.616*bm["sig2"]-0.147*bm["phi"]+0.210*bm["phi"]**2
bm["S_trend"]=-0.17*bm["phi"]+0.09*bm["phi"]**2
bm["S_phi2"]=bm["phi"]**2
def lagmap(col):
    me=bm.groupby("ym")[col].last(); yms=sorted(me.index); nxt={yms[i]:yms[i+1] for i in range(len(yms)-1)}
    lag={nxt[k]:v for k,v in me.items() if k in nxt}; return dt["ym"].map(lag).values
for c in ["S_faith","S_krfit","S_trend","S_phi2","phi"]: dt[c]=lagmap(c)

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
    db=np.abs(np.diff(np.r_[1.0,beta]))
    return dt["beta_R05_V5"].values*beta*dt["m4_weight_lag"].values*dt["ret_orig"].values - db*0.0015 - dt["db_R05_V5"].values*0.0015
def perf(x):
    x=np.asarray(x,float); x=x[np.isfinite(x)]; nav=np.cumprod(1+x); mdd=1-np.min(nav/np.maximum.accumulate(nav)); cagr=nav[-1]**(12/len(x))-1
    return x.mean()/x.std()*np.sqrt(12),cagr,mdd,(cagr/mdd if mdd>0 else np.nan)
def nwt(dd):
    dd=dd[np.isfinite(dd)]; n=len(dd); e=dd-dd.mean(); ss=(e@e)/n
    for l in range(1,4): ss+=2*(1-l/4)*((e[l:]@e[:-l])/n)
    return dd.mean()/np.sqrt(ss/n)
retAR=dt["ret_L5_V5"].values
g2008=((dt["anchor_date"]>="2007-06-01")&(dt["anchor_date"]<="2009-06-01")).values
def dd2008(x): xx=x[g2008]; xx=xx[np.isfinite(xx)]; nav=np.cumprod(1+xx); return (1-np.min(nav/np.maximum.accumulate(nav)))*100

srA,cgA,mdA,caA=perf(retAR)
log(f"현 book(AR): SR {srA:.3f} MDD {mdA*100:.1f}% Calmar {caA:.3f} | 2008 DD {dd2008(retAR):.1f}%")
log(f"\n=== β_AR → 논문④ 신호별 (전기간, 신호 vs AR) ===")
log(f"  {'신호':>16} {'SR':>6} {'MDD':>7} {'Calmar':>7} {'ΔSR':>7} {'paired-t':>9} {'2008DD':>7}")
betas={}
for col,nm in [("S_faith","충실(논문계수)"),("S_krfit","충실(KR-fit)"),("S_trend","trend-only 비대칭"),("S_phi2","ϕ²(구, 대칭)")]:
    b=build_beta(dt[col].values); betas[col]=b; rn=ret_of(b); sr,cg,md,ca=perf(rn); t=nwt(rn-retAR)
    log(f"  {nm:>16} {sr:6.3f} {md*100:6.1f}% {ca:7.3f} {sr-srA:+7.3f} {t:+9.2f} {dd2008(rn):6.1f}%")

# 비대칭 검증: 상승추세(ϕ>0) vs 하락추세(ϕ<0) 월의 평균 β (충실 vs ϕ²)
up=dt["phi"].values>0; dn=dt["phi"].values<0
log(f"\n=== 비대칭 검증: 상승추세(ϕ>0) vs 하락추세(ϕ<0) 평균 de-risk β ===")
for col,nm in [("S_faith","충실"),("S_phi2","ϕ²(구)")]:
    b=betas[col]; log(f"  {nm:>8}: 상승월 β̄ {np.nanmean(b[up]):.3f} | 하락월 β̄ {np.nanmean(b[dn]):.3f}  (하락<상승이면 하락서 더 방어=논문 의도)")

# 충실(논문계수) 구간별
log(f"\n=== 충실(논문계수) 구간별 vs AR ===")
b=betas["S_faith"]; rn=ret_of(b)
for msk,lab in [(np.ones(len(dt),bool),"전기간"),((dt['anchor_date']>='2009-02-01').values,"2009+"),((dt['anchor_date']<'2010-01-01').values,"GFC구간"),(dt['regime'].isin(['CRISIS','CAUTION']).values,"방어국면")]:
    a1=perf(retAR[msk]); a2=perf(rn[msk]); log(f"  [{lab:>8}] AR: SR{a1[0]:+.2f} MDD{a1[2]*100:.0f}% | 충실: SR{a2[0]:+.2f} MDD{a2[2]*100:.0f}%")
log("\n판정: 충실(비대칭 포함)이 ϕ²보다 2008DD↓ & paired-t>2 & 하락월 더 방어 → 충실구현이 진짜 우위. AR 초과여부 확인.")
log("=== done ===")
