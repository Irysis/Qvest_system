# Round 5 — 장기 horizon long-only 게이트 (Round4 LEAD: 3-12M서 유동성/idiovol/이익리비전 최근 IC강)
#   PIT trailing-IC composite + 사전약정 경제 composite. long-only top-25, 비중첩 리밸.
#   판정: 최근(2021-26) net PORT_t/IR + 회전율 + basket 유동성(RF-A5 체크). IC가 게이트 살아남나.
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/round5_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")

pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in pan.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]
pan[fcols]=pan[fcols].fillna(0.0)
# 월간 로그수익 + Size(유동성 proxy) + bm
rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Ret","Size","Close","Vol"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd=rd.dropna(subset=["Ret"])
rd["lr"]=np.log1p(rd["Ret"].clip(-0.99)); rd["tv"]=rd["Close"]*rd["Vol"]
g=rd.sort_values(["Ticker","Date"]).groupby(["Ticker","ym"])
mret=g.agg(lr=("lr","sum"), Size=("Size","last"), tv=("tv","mean")).reset_index().sort_values(["Ticker","ym"])
def fwdH(s,H):
    a=s.values; o=np.full(len(a),np.nan)
    for i in range(len(a)):
        if i+H<len(a): o[i]=np.expm1(a[i+1:i+1+H].sum())
    return o
for H in (3,6): mret[f"F{H}"]=mret.groupby("Ticker")["lr"].transform(lambda s:pd.Series(fwdH(s,H),index=s.index))
df=pan.merge(mret[["Ticker","ym","Size","tv","F3","F6"]],on=["Ticker","ym"],how="left")
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmlr=bm.groupby("ym")[bc].apply(lambda r:np.log1p(r).sum())
def bmfwdH(t,H):
    idx=list(bmlr.index)
    if t not in idx: return np.nan
    i=idx.index(t);
    return np.expm1(bmlr.iloc[i+1:i+1+H].sum()) if i+1+H<=len(idx) else np.nan

months=sorted(df["ym"].unique()); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
Fmat=df[fcols].values; ymarr=df["ym"].values; tkv=df["Ticker"].values; szv=df["Size"].values

# 팩터별 H-horizon 월별 IC (PIT용)
def factor_ic(H):
    fc=f"F{H}"; d=df.dropna(subset=[fc]); out={}
    for f in fcols:
        out[f]=d.groupby("ym").apply(lambda gg: gg[f].corr(gg[fc],method="spearman"))
    return pd.DataFrame(out).reindex(months)

PRE={ # 사전약정 경제 composite (부호: +면 high=good). 존재하는 것만 사용.
 "L14_Price_Impact":+1,"L40_VWAP_Spread":+1,"L01_Amihud":+1,"D01_IdioVol":+1,
 "R12_Idiosyncratic_Risk":+1,"C04_ESBR":+1,"C05_ESCR":+1,"V01_BM":+1,"V14_EBIT_EV":+1}
PRE={k:v for k,v in PRE.items() if k in fcols}

def backtest_H(sigfun, H, name):
    IC=factor_ic(H) if sigfun=="dynIC" else None
    dec=[m for m in OOS if midx[m]%H==0]   # 비중첩 리밸
    rec=[]; prevsel=set(); szpct=[]
    for t in dec:
        # PIT trailing IC: realized ≤ t (m+H ≤ t → m ≤ t-H)
        te=np.where(ymarr==t)[0]
        if len(te)<25: continue
        if sigfun=="dynIC":
            cutm=[m for m in months if midx[m]<=midx[t]-H]
            tr=IC.loc[cutm].tail(24).mean().values; tr=np.nan_to_num(tr)
            sig=Fmat[te]@tr
        else:  # pre-committed
            w=np.array([PRE.get(f,0) for f in fcols],dtype=float)
            sig=Fmat[te]@w
        idx=np.argpartition(-sig,min(25,len(sig)-1))[:25]; sel=set(tkv[te][idx])
        fwd=df[f"F{H}"].values[te][idx]; gross=np.nanmean(fwd)
        bmf=bmfwdH(t,H)
        to=2*(25-len(sel&prevsel))/25 if prevsel else 1.0
        net=gross-to*0.0015
        # basket 유동성: 선택종목 Size 백분위(유니버스 내)
        allsz=szv[te]; selsz=szv[te][idx]
        szpct.append(np.mean([ (allsz<s).mean() for s in selsz if not np.isnan(s)]))
        rec.append((t,net,bmf)); prevsel=sel
    r=pd.DataFrame(rec,columns=["ym","net","bm"]).dropna()
    def ir(lo=None,hi=None):
        x=r if lo is None else r[(r["ym"]>=lo)&(r["ym"]<=hi)]
        if len(x)<4: return np.nan
        a=x["net"].values-x["bm"].values; return a.mean()/a.std()*np.sqrt(12/H)
    log(f"{name:30s} H{H} n{len(r)} | full IR {ir():+.2f} | 10-15 {ir('2010-01','2015-12'):+.2f} | 16-20 {ir('2016-01','2020-12'):+.2f} | 21-26 {ir('2021-01','2026-12'):+.2f} | szPct {np.nanmean(szpct):.2f}")

log(f"=== Round 5 장기 horizon long-only (top25, 비중첩, net 15bps). szPct=선택종목 Size 백분위(유니버스내,높을수록 대형) ===")
for H in (3,6):
    backtest_H("dynIC",H,"PIT trailing-IC composite")
    backtest_H("pre",H,"pre-committed 경제 composite")
log("\n판정: 21-26 IR 양수+유의 & szPct 너무 낮지않음(비유동집중 아님)이면 LEAD 생존 → 다음 정밀게이트.")
log("=== done ===")
