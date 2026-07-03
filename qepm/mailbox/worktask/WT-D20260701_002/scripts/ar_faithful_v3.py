# 충실 논문④ 오버레이 v3 — (A)호라이즌 견고성 (B)KR계수 최적화 필요? (C)AR+충실 결합. 전기간 PIT.
import pandas as pd, numpy as np, pyarrow.parquet as pq, warnings
warnings.filterwarnings("ignore")
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"
BT=ROOT+"/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results"
OUT=CACHE+"/discovery/ar_faithful_v3_results.txt"; open(OUT,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="utf-8") as f: f.write(s+"\n")
dt=pd.read_csv(BT+"/period_returns_layer5.csv"); dt["anchor_date"]=pd.to_datetime(dt["anchor_date"])
dt=dt[np.isfinite(dt["ret_orig"])].sort_values("anchor_date").reset_index(drop=True); dt["ym"]=dt["realized_ym"].astype(str).str[:7]
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["Date"]=pd.to_datetime(bm["Date"]); bm=bm.dropna(subset=[bc]).sort_values("Date").reset_index(drop=True)
r=bm[bc].values; s=pd.Series(r); mu=s.rolling(252,min_periods=120).mean(); sd=s.rolling(252,min_periods=120).std()
rhat=np.clip(((s-mu)/(sd+1e-12)).values,-20,20); bm["ym"]=bm["Date"].dt.strftime("%Y-%m")
al=1-np.exp(-1/16); sig2=np.full(len(rhat),np.nan); acc=1.0
for t in range(len(rhat)):
    if np.isfinite(rhat[t]): acc=al*rhat[t]**2+(1-al)*acc; sig2[t]=acc
bm["sig2"]=sig2; ry2=np.r_[rhat[1:]**2,np.nan]   # r̂²_{t+1}
def phi_of(T):
    Nmax=6*T; nn=np.arange(Nmax+1); w=nn*np.exp(-2*nn/T); w=w/np.sqrt((w**2).sum()); p=np.full(len(rhat),np.nan)
    for t in range(Nmax,len(rhat)): p[t]=np.clip(np.dot(w,rhat[t-Nmax:t+1][::-1]),-2.5,2.5)
    return p
def lagmap(dailycol_series):
    me=dailycol_series.groupby(bm["ym"]).last(); yms=sorted(me.index); nxt={yms[i]:yms[i+1] for i in range(len(yms)-1)}
    lag={nxt[k]:v for k,v in me.items() if k in nxt}; return dt["ym"].map(lag).values
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
def perf(x):
    x=np.asarray(x,float); x=x[np.isfinite(x)]; nav=np.cumprod(1+x); mdd=1-np.min(nav/np.maximum.accumulate(nav)); cagr=nav[-1]**(12/len(x))-1
    return x.mean()/x.std()*np.sqrt(12),cagr,mdd,(cagr/mdd if mdd>0 else np.nan)
def nwt(dd):
    dd=dd[np.isfinite(dd)]; n=len(dd); e=dd-dd.mean(); ss=(e@e)/n
    for l in range(1,4): ss+=2*(1-l/4)*((e[l:]@e[:-l])/n)
    return dd.mean()/np.sqrt(ss/n)
retAR=dt["ret_L5_V5"].values; srA,_,mdA,caA=perf(retAR)
g08=((dt["anchor_date"]>="2007-06-01")&(dt["anchor_date"]<="2009-06-01")).values
def dd08(x): xx=x[g08]; xx=xx[np.isfinite(xx)]; nav=np.cumprod(1+xx); return (1-np.min(nav/np.maximum.accumulate(nav)))*100
log(f"현 book(AR): SR {srA:.3f} MDD {mdA*100:.1f}% Calmar {caA:.3f} 2008DD {dd08(retAR):.1f}%\n")

# 신호별 β_AR 교체 헬퍼
def swap_perf(sig,lab):
    b=build_beta(sig); rn=ret_of(b); sr,_,md,ca=perf(rn); t=nwt(rn-retAR)
    log(f"  {lab:>26} SR {sr:.3f} MDD {md*100:.1f}% Calmar {ca:.3f} ΔSR {sr-srA:+.3f} paired-t {t:+.2f} 2008DD {dd08(rn):.1f}%")
    return b,rn

# ===== (A) 호라이즌 견고성 (충실 논문계수) =====
log("=== (A) 호라이즌 견고성 (충실 논문계수 0.13+0.79σ²-0.17ϕ+0.09ϕ²) ===")
for T in [8,16,32,64]:
    p=phi_of(T); Sf=lagmap(pd.Series(0.13+0.79*bm["sig2"].values-0.17*p+0.09*p**2))
    swap_perf(Sf,f"충실 T={T}")
log("  (trend-only -0.17ϕ+0.09ϕ²)")
for T in [8,16,32]:
    p=phi_of(T); St=lagmap(pd.Series(-0.17*p+0.09*p**2)); swap_perf(St,f"trend-only T={T}")

# ===== (B) KR 계수 최적화 필요? T=16 =====
log("\n=== (B) KR 계수 최적화 필요? (T=16, 논문계수 vs PIT-expanding-KR-fit vs full-sample-KR-fit) ===")
T=16; p16=phi_of(T)
# 논문계수
swap_perf(lagmap(pd.Series(0.13+0.79*bm["sig2"].values-0.17*p16+0.09*p16**2)),"논문계수 (fitting 0)")
# full-sample KR-fit (look-ahead upper bound)
X=np.column_stack([np.ones(len(rhat)),bm["sig2"].values,p16,p16**2]); m=np.isfinite(ry2)&np.isfinite(bm["sig2"].values)&np.isfinite(p16)
bfull=np.linalg.lstsq(X[m],ry2[m],rcond=None)[0]
log(f"    [full-sample KR coef] a{bfull[0]:+.3f} d{bfull[1]:+.3f} e{bfull[2]:+.3f} f{bfull[3]:+.3f}")
swap_perf(lagmap(pd.Series(X@bfull)),"full-sample KR-fit(look-ahead)")
# PIT expanding KR-fit: 매 월말 과거 전체로 refit
Sp=np.full(len(rhat),np.nan); bm_dates=bm["Date"].values
me_dates=bm.groupby("ym")["Date"].last().values
coef_at={}
for d in me_dates:
    mm=(bm_dates<=d)&np.isfinite(ry2)&np.isfinite(bm["sig2"].values)&np.isfinite(p16)
    if mm.sum()<250: continue
    try: coef_at[d]=np.linalg.lstsq(X[mm],ry2[mm],rcond=None)[0]
    except: pass
# 각 일자에 '가장 최근 월말 refit 계수' 적용
last=None; order=np.argsort(bm_dates)
for i in order:
    d=bm_dates[i]
    for md in me_dates:
        if md<=d: last=coef_at.get(md,last)
    if last is not None and np.isfinite(bm["sig2"].values[i]) and np.isfinite(p16[i]):
        Sp[i]=last[0]+last[1]*bm["sig2"].values[i]+last[2]*p16[i]+last[3]*p16[i]**2
swap_perf(lagmap(pd.Series(Sp)),"PIT-expanding KR-fit")
log("  판독: 논문계수 ≈ PIT-KR-fit이면 → KR 최적화 불필요(robust). full-sample만 크게 좋으면 → 과적합 위험.")

# ===== (C) AR + 충실 결합 =====
log("\n=== (C) AR + 충실 결합 (2008=AR · 평시=충실) T=16 ===")
bF,rF=swap_perf(lagmap(pd.Series(0.13+0.79*bm["sig2"].values-0.17*p16+0.09*p16**2)),"충실 단독(참조)")
bAR=dt["beta_threshold_lag"].values
# min: 매월 더 방어적인 쪽 (AR 크래시 + 충실 추세 둘 다 반영)
bmin=np.minimum(bAR,bF);
def ret_full(beta):  # β_AR자리에 결합β
    db=np.abs(np.diff(np.r_[1.0,beta])); return dt["beta_R05_V5"].values*beta*dt["m4_weight_lag"].values*dt["ret_orig"].values - db*0.0015 - dt["db_R05_V5"].values*0.0015
for beta,lab in [(np.minimum(bAR,bF),"min(AR,충실) 결합"),(bAR*bF,"AR×충실 결합(stack)")]:
    rn=ret_full(beta); sr,_,md,ca=perf(rn); t=nwt(rn-retAR)
    log(f"  {lab:>26} SR {sr:.3f} MDD {md*100:.1f}% Calmar {ca:.3f} ΔSR {sr-srA:+.3f} paired-t {t:+.2f} 2008DD {dd08(rn):.1f}%")
log("  목표: 결합이 2008DD를 AR수준(9.3%)으로 지키면서 SR도 충실수준(1.88)이면 = 최선.")
log("=== done ===")
