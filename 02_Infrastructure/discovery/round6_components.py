# Round 6 — Round5 사전약정 composite 최근-양수의 성분 분해 + 유의성(t)
#   성분: value / earnings-revision / idiovol / illiquidity. H=3,6 long-only top25 비중첩.
#   판정: 어느 성분이 최근 끌고 t-유의한가. value-decay와 정합? (저전력 주의 — t 명시)
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/round6_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")
pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in pan.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]; pan[fcols]=pan[fcols].fillna(0.0)
rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Ret","Size"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd=rd.dropna(subset=["Ret"]); rd["lr"]=np.log1p(rd["Ret"].clip(-0.99))
mret=rd.sort_values(["Ticker","Date"]).groupby(["Ticker","ym"]).agg(lr=("lr","sum"),Size=("Size","last")).reset_index().sort_values(["Ticker","ym"])
def fwdH(s,H):
    a=s.values;o=np.full(len(a),np.nan)
    for i in range(len(a)):
        if i+H<len(a): o[i]=np.expm1(a[i+1:i+1+H].sum())
    return o
for H in (3,6): mret[f"F{H}"]=mret.groupby("Ticker")["lr"].transform(lambda s:pd.Series(fwdH(s,H),index=s.index))
df=pan.merge(mret[["Ticker","ym","Size","F3","F6"]],on=["Ticker","ym"],how="left")
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc]); bmlr=bm.groupby("ym")[bc].apply(lambda r:np.log1p(r).sum())
idxb=list(bmlr.index)
def bmfwdH(t,H):
    if t not in idxb: return np.nan
    i=idxb.index(t); return np.expm1(bmlr.iloc[i+1:i+1+H].sum()) if i+1+H<=len(idxb) else np.nan
months=sorted(df["ym"].unique()); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
Fmat=df[fcols].values; ymarr=df["ym"].values; tkv=df["Ticker"].values; szv=df["Size"].values
COMP={
 "value":["V01_BM","V14_EBIT_EV"], "earnings":["C04_ESBR","C05_ESCR"],
 "idiovol":["D01_IdioVol","R12_Idiosyncratic_Risk"], "illiq":["L14_Price_Impact","L40_VWAP_Spread"],
 "all":["V01_BM","V14_EBIT_EV","C04_ESBR","C05_ESCR","D01_IdioVol","R12_Idiosyncratic_Risk","L14_Price_Impact","L40_VWAP_Spread"]}
COMP={k:[f for f in v if f in fcols] for k,v in COMP.items()}
def bt(comp,H):
    w=np.array([1.0 if f in comp else 0 for f in fcols])
    dec=[m for m in OOS if midx[m]%H==0]; rec=[]; prev=set(); szp=[]
    for t in dec:
        te=np.where(ymarr==t)[0]
        if len(te)<25: continue
        sig=Fmat[te]@w; idx=np.argpartition(-sig,min(25,len(sig)-1))[:25]; sel=set(tkv[te][idx])
        gross=np.nanmean(df[f"F{H}"].values[te][idx]); to=2*(25-len(sel&prev))/25 if prev else 1.0
        allsz=szv[te]; szp.append(np.nanmean([(allsz<s).mean() for s in szv[te][idx] if not np.isnan(s)]))
        rec.append((t,gross-to*0.0015,bmfwdH(t,H))); prev=sel
    r=pd.DataFrame(rec,columns=["ym","net","bm"]).dropna()
    def stat(lo,hi):
        x=r[(r["ym"]>=lo)&(r["ym"]<=hi)];
        if len(x)<4: return (np.nan,np.nan,0)
        a=x["net"].values-x["bm"].values; ir=a.mean()/a.std()*np.sqrt(12/H); t=a.mean()/a.std()*np.sqrt(len(a)); return (ir,t,len(a))
    ir,tt,n=stat("2021-01","2026-12"); fir,_,_=stat("2005-01","2026-12")
    return fir,ir,tt,n,np.nanmean(szp)
log("=== Round 6 성분분해 (long-only top25, net). 최근=2021-26. t=유의성(저전력 주의) ===")
log(f"{'component':12s} {'H':>2} {'full_IR':>8} {'21-26_IR':>9} {'21-26_t':>8} {'n':>3} {'szPct':>6}")
for H in (3,6):
    for k,c in COMP.items():
        if not c: continue
        fir,ir,tt,n,sz=bt(c,H)
        log(f"{k:12s} {H:>2} {fir:8.2f} {ir:9.2f} {tt:8.2f} {n:>3} {sz:6.2f}{'  <-t>2' if tt>2 else ''}")
log("\n판정: 최근 t>2 성분이 있으면 진짜 리드. 전부 t<1.7이면 저전력 noise → 횡단면 selection 소진 확정.")
log("=== done ===")
