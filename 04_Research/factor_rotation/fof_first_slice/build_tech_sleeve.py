"""build_tech_sleeve.py — 제외된 technical 12팩터를 RAWDATA 일봉서 계산 → sleeve → FoF와 직교성/PORT_t.
방향: lower_better(RSI14/RSI28/HLRange/AutoCorr=리버설·저변동) / higher_better(PMA·BB·OBV·MFI·Gap=모멘텀).
3 sleeve: TECH_rev(리버설계열) / TECH_mom(모멘텀계열) / TECH_all(전체). 월간 top-25 long-only 15bps, active vs BM.
"""
import os, numpy as np, pandas as pd, pyarrow.parquet as pq
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
def nw_t(x,lag=3):
    x=np.asarray(x); x=x[~np.isnan(x)]; n=len(x)
    if n<5: return np.nan
    e=x-x.mean(); s=(e@e)/n
    for l in range(1,lag+1): s+=2*(1-l/(lag+1))*((e[l:]@e[:-l])/n)
    return x.mean()/np.sqrt(s/n) if s>0 else np.nan
rd=pq.read_table(R+"/.cache/RAWDATA.parquet",columns=["Date","Ticker","Open","High","Low","Close","Vol","Ret","BM_Ret"]).to_pandas()
rd["Date"]=pd.to_datetime(rd["Date"]); rd=rd.sort_values(["Ticker","Date"]).reset_index(drop=True)
rd["ym"]=rd["Date"].dt.strftime("%Y-%m")
g=rd.groupby("Ticker",group_keys=False)
def rsi(c,n):
    d=c.diff(); up=d.clip(lower=0); dn=(-d).clip(lower=0)
    au=up.ewm(alpha=1/n,adjust=False).mean(); ad=dn.ewm(alpha=1/n,adjust=False).mean()
    return 100-100/(1+au/ad.replace(0,np.nan))
print("computing daily technicals...")
rd["T01_RSI14"]=g["Close"].apply(lambda c: rsi(c,14))
rd["T10_RSI28"]=g["Close"].apply(lambda c: rsi(c,28))
rd["T03_BB20"]=g["Close"].apply(lambda c: (c-c.rolling(20).mean())/(2*c.rolling(20).std()))
for n in (5,20,60,120): rd[f"T0{ {5:6,20:7,60:8,120:9}[n] }_PMA{n}"]=g["Close"].apply(lambda c: c/c.rolling(n).mean()-1)
rd["obv"]=(np.sign(rd["Ret"].fillna(0))*rd["Vol"].fillna(0))
rd["T04_OBV21"]=g["obv"].apply(lambda o: o.cumsum()-o.cumsum().shift(21))
tp=(rd["High"]+rd["Low"]+rd["Close"])/3; rmf=tp*rd["Vol"]; rd["tp"]=tp; rd["rmf"]=rmf
rd["pos"]=np.where(g["tp"].diff()>0,rd["rmf"],0.0); rd["neg"]=np.where(g["tp"].diff()<0,rd["rmf"],0.0)
rd["T05_MFI14"]=100-100/(1+g["pos"].apply(lambda s:s.rolling(14).sum())/g["neg"].apply(lambda s:s.rolling(14).sum()).replace(0,np.nan))
rd["T13_Gap"]=(rd["Open"]-g["Close"].shift(1))/g["Close"].shift(1)
rd["T14_HLRange"]=(rd["High"]-rd["Low"])/rd["Open"]
rd["T15_AutoCorr"]=g["Ret"].apply(lambda r: r.rolling(21).corr(r.shift(1)))
rd["tv"]=rd["Close"]*rd["Vol"]; rd["adv"]=g["tv"].apply(lambda s:s.rolling(20).mean())
TECH=["T01_RSI14","T10_RSI28","T03_BB20","T06_PMA5","T07_PMA20","T08_PMA60","T09_PMA120","T04_OBV21","T05_MFI14","T13_Gap","T14_HLRange","T15_AutoCorr"]
DIR={"T01_RSI14":-1,"T10_RSI28":-1,"T14_HLRange":-1,"T15_AutoCorr":-1,"T03_BB20":1,"T04_OBV21":1,"T05_MFI14":1,"T06_PMA5":1,"T07_PMA20":1,"T08_PMA60":1,"T09_PMA120":1,"T13_Gap":1}
# 월말 스냅샷 (PIT) + 월간 realized return + adv
mo=rd.groupby(["Ticker","ym"]).agg({**{t:"last" for t in TECH},"adv":"last","Ret":lambda r:np.expm1(np.log1p(r.clip(-0.99)).sum()),"BM_Ret":lambda r:np.expm1(np.log1p(r).sum())}).reset_index()
mo=mo.sort_values(["Ticker","ym"])
mo["fwd"]=mo.groupby("Ticker")["Ret"].shift(-1)   # t→t+1 realized
bm=mo.groupby("ym")["BM_Ret"].first().reset_index().sort_values("ym"); bm["bmfwd"]=bm["BM_Ret"].shift(-1); bmmap=dict(zip(bm.ym,bm.bmfwd))
mo=mo[mo["adv"]>=2e8].copy()   # 유동
print("monthly liquid panel:",len(mo),"tickers/month~",mo.groupby('ym').size().median())
def z(s): return (s-s.mean())/(s.std()+1e-9)
def sleeve(cols):
    d=mo.dropna(subset=["fwd"]).copy()
    d["score"]=0.0
    for c in cols:
        d["score"]=d["score"]+d.groupby("ym")[c].transform(z).fillna(0)*DIR[c]
    rec=[]; prev=set()
    for t,x in d.groupby("ym"):
        x=x.dropna(subset=["score"]);
        if len(x)<25 or t not in bmmap or np.isnan(bmmap[t]): continue
        top=x.nlargest(25,"score"); sel=set(top["Ticker"]); to=len(sel^prev)/25 if prev else 1.0
        rec.append((t,top["fwd"].mean()-0.0015*to,bmmap[t])); prev=sel
    r=pd.DataFrame(rec,columns=["ym","net","bm"]).dropna(); r["act"]=r.net-r.bm
    return r
REV=["T01_RSI14","T10_RSI28","T14_HLRange","T15_AutoCorr"]; MOM=["T03_BB20","T04_OBV21","T05_MFI14","T06_PMA5","T07_PMA20","T08_PMA60","T09_PMA120","T13_Gap"]
S={"TECH_rev":sleeve(REV),"TECH_mom":sleeve(MOM),"TECH_all":sleeve(TECH)}
def ir(a): a=a[~np.isnan(a)]; return a.mean()/a.std()*np.sqrt(12) if a.std()>0 else np.nan
fof=pd.read_csv(OUT+"/stack_fof_active.csv")[["ym","act_fof"]]
print("\n=== technical sleeve standalone + FoF 직교성 ===")
res=fof.copy()
for nm,r in S.items():
    m=fof.merge(r[["ym","act"]].rename(columns={"act":nm}),on="ym").dropna()
    a=m[nm].values; ar=m.loc[m.ym>='2021-01',nm].values
    rho=np.corrcoef(m["act_fof"],m[nm])[0,1]
    print(f"  {nm:9s}: full PORT_t={nw_t(a):+.2f} IR={ir(a):+.2f} | recent PORT_t={nw_t(ar):+.2f} IR={ir(ar):+.2f} | ρ(FoF)={rho:+.2f} n={len(m)}")
    res=res.merge(r[["ym","act"]].rename(columns={"act":nm}),on="ym",how="left")
# 최선 후보로 2-sleeve stack
best=max(S,key=lambda k: (lambda a: nw_t(fof.merge(S[k][["ym","act"]].rename(columns={"act":k}),on="ym")[k].values))(k))
m=res.dropna(subset=["act_fof",best])
comb=0.5*m["act_fof"]+0.5*m[best]
print(f"\n  best={best}: FoF+{best} EW stack full IR={ir(comb.values):+.2f} PORT_t={nw_t(comb.values):+.2f} (FoF 단독 IR={ir(m['act_fof'].values):+.2f})")
res.to_csv(OUT+"/tech_sleeve_series.csv",index=False); print("saved.")
