# Round 8 — 3M earnings-revision sleeve 정밀 게이트 + book-marginal
#   sleeve: earnings family composite, 분기 리밸·월간 마킹 → NW PORT_t·calmar·turnover.
#   book-marginal: book(ret_L5_V5) 최근 SR/calmar vs book+sleeve 결합. ΔSR.
import pandas as pd, numpy as np, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/round8_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")
pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in pan.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]; pan[fcols]=pan[fcols].fillna(0.0)
EARNB=[f for f in ["C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C05_ESCR","C06_TP_Gap","C19_Composite_Earnings"] if f in fcols]
log(f"earnings family: {EARNB}")
# bm 월간
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmm=bm.groupby("ym")[bc].apply(lambda r:np.expm1(np.log1p(r).sum()))
months=sorted(pan["ym"].unique()); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
w=np.array([1.0 if f in EARNB else 0 for f in fcols])
Fmat=pan[fcols].values; ymarr=pan["ym"].values; tkv=pan["Ticker"].values; fwdm=pan["fwd_ret_1m"].values

# sleeve 월간: 분기(3M) 리밸, 월간 마킹. 결정월 t에서 선택 → t,t+1,t+2 보유.
held=None; rb_at=None; rows=[]
for m in OOS:
    if midx[m]%3==0 or held is None:
        te=np.where(ymarr==m)[0]
        if len(te)>=25:
            sig=Fmat[te]@w; idx=np.argpartition(-sig,min(25,len(sig)-1))[:25]
            newsel=set(tkv[te][idx]); to=(2*(25-len(newsel&held))/25 if held else 1.0); held=newsel; rb=True
        else: rb=False; to=0.0
    else: rb=False; to=0.0
    # 이번달 보유바스켓 수익 = fwd_ret_1m(this month) mean over held
    te=np.where(ymarr==m)[0]; mt=pan.iloc[te]; basket=mt[mt["Ticker"].isin(held)]
    gross=basket["fwd_ret_1m"].mean()
    net=gross-(to*0.0015 if rb else 0.0)
    rows.append((m,net,bmm.get(m,np.nan),to if rb else 0.0))
sl=pd.DataFrame(rows,columns=["ym","net","bm","to"]).dropna(subset=["net","bm"])

def nw_t(x,lag=3):
    x=x[~np.isnan(x)]; n=len(x);
    if n<5: return np.nan
    e=x-x.mean(); s=(e@e)/n
    for l in range(1,lag+1): s+=2*(1-l/(lag+1))*((e[l:]@e[:-l])/n)
    return x.mean()/np.sqrt(s/n)
def mdd(r): nav=np.cumprod(1+r); return 1-np.min(nav/np.maximum.accumulate(nav))
def gate(d,tag):
    r=d["net"].values; a=r-d["bm"].values; n=len(r)
    cagr=np.prod(1+r)**(12/n)-1; m=mdd(r)
    log(f"  {tag:14s} n{n} absSR {r.mean()/r.std()*np.sqrt(12):+.2f} CAGR {cagr*100:+.1f}% MDD {m*100:.1f}% calmar {cagr/m:+.2f} | activeIR {a.mean()/a.std()*np.sqrt(12):+.2f} PORT_t(NW3) {nw_t(a):+.2f} TO {d['to'].mean()*12:.1f}")

log("\n=== 3M earnings sleeve 정밀 게이트 (월간마킹·분기리밸) ===")
gate(sl,"full")
gate(sl[sl["ym"]>="2021-01"],"recent 21-26")
gate(sl[(sl["ym"]>="2010-01")&(sl["ym"]<="2015-12")],"2010-15")
gate(sl[(sl["ym"]>="2016-01")&(sl["ym"]<="2020-12")],"2016-20")
log("  per-year recent active(%):")
for y in ["2021","2022","2023","2024","2025","2026"]:
    g=sl[sl["ym"].str[:4]==y]
    if len(g): a=(g["net"]-g["bm"]); log(f"    {y}: {a.sum()*100:+.1f}%  (n{len(g)})")

# book (ret_L5_V5) + book-marginal
L5=pd.read_csv(ROOT+"/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
L5["ym"]=L5["realized_ym"].str[:7]; bk=L5[["ym","ret_L5_V5"]].dropna()
mrg=sl.merge(bk,on="ym",how="inner")
log("\n=== book-marginal (book=ret_L5_V5, 최근 2021-26) ===")
def srcal(r):
    r=np.array(r); n=len(r); cagr=np.prod(1+r)**(12/n)-1; m=mdd(r); return r.mean()/r.std()*np.sqrt(12), cagr/m
for tag,lo in [("full",None),("recent",2021)]:
    d=mrg if lo is None else mrg[mrg["ym"]>=f"{lo}-01"]
    if len(d)<6: continue
    bsr,bcal=srcal(d["ret_L5_V5"].values); ssr,scal=srcal(d["net"].values)
    for blend in [(1.0,0.0),(0.8,0.2),(0.7,0.3),(0.5,0.5)]:
        comb=blend[0]*d["ret_L5_V5"].values+blend[1]*d["net"].values
        csr,ccal=srcal(comb)
        if blend==(1.0,0.0): log(f"  [{tag}] book단독 SR {csr:+.2f} calmar {ccal:+.2f}")
        else: log(f"  [{tag}] book{int(blend[0]*100)}/sleeve{int(blend[1]*100)} SR {csr:+.2f}(Δ{csr-bsr:+.2f}) calmar {ccal:+.2f}")
log("\n판정: recent PORT_t(NW)>2.95 & calmar>0.64 & book+sleeve ΔSR>0(특히 최근) → capital 후보. forward holdout 사전등록 필수(최근=search기간).")
log("=== done ===")
