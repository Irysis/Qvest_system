# Round 10 — earnings sleeve를 book에 대해 직교화(residualize). Round9 실패 메커니즘 공략.
#   Round9: 슬리브 raw-blend ΔactiveIR<0 (corr 0.60 + IR 0.34<book 0.61). 블로커=상관.
#   가설: book이 못 가진 직교 earnings-alpha가 남아있나? 잔차 IR≥~0.25면 ΔIR≥0.05 가능.
#   ① PIT 확장윈도 beta로 sleeve_active를 book_active에 직교화 → 잔차 mean/IR
#   ② 최적 결합 ΔactiveIR = sqrt(book_IR²+resid_IR²)−book_IR (직교시) 실측 대조
#   ③ conviction 변형도 (robustness)
#   판정: recent 잔차 ΔactiveIR≥0.05 → 직교 earnings-alpha 실재(tradeable 구성 Round11)
#         <0.05 → earnings ⊂ book (book-marginal 기준 소진 확정)
import pandas as pd, numpy as np, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/round10_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")

# sleeve(ew default) — round9 저장본 재사용 + conviction 재빌드
sl_ew=pd.read_csv(OUT+"/round9_default_series.csv")  # ym, ret_net, benchmark_ret
sl_ew=sl_ew.rename(columns={"ret_net":"sl_net","benchmark_ret":"bm"})

# conviction 변형 재빌드 (round9와 동일 구성, sizing=conviction)
pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in pan.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]; pan[fcols]=pan[fcols].fillna(0.0)
fi={f:j for j,f in enumerate(fcols)}
BROAD=[f for f in ["C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C05_ESCR","C06_TP_Gap","C19_Composite_Earnings"] if f in fi]
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmm=bm.groupby("ym")[bc].apply(lambda r:np.expm1(np.log1p(r).sum()))
rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Close","Vol"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd["tv"]=rd["Close"]*rd["Vol"]
mliq=rd.groupby(["Ticker","ym"])["tv"].mean().reset_index().sort_values(["Ticker","ym"])
mliq["tv_lag"]=mliq.groupby("Ticker")["tv"].shift(1); LIQOK=set(map(tuple,mliq.loc[mliq["tv_lag"]>=2e8,["ym","Ticker"]].values))
months=sorted(pan["ym"].unique()); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
Fmat=pan[fcols].values; ymarr=pan["ym"].values; tkv=pan["Ticker"].values; fwdm=pan["fwd_ret_1m"].values
def build(sizing):
    w=np.array([1.0 if f in BROAD else 0 for f in fcols]); held=None; rows=[]
    for m in OOS:
        i=midx[m]; decide=(i%3==0) or held is None; te=np.where(ymarr==m)[0]; to=0.0
        if decide and len(te)>=25:
            ct=tkv[te]; cs=Fmat[te]@w; pool=[k for k in range(len(te)) if (m,ct[k]) in LIQOK]
            if len(pool)<25: pool=list(range(len(te)))
            pool=np.array(pool); ps=cs[pool]; loc=pool[np.argpartition(-ps,min(25,len(ps)-1))[:25]]
            stk=ct[loc]; ssig=cs[loc]
            nw=(pd.Series(ssig).rank().values/pd.Series(ssig).rank().values.sum()) if sizing=="conv" else np.full(len(stk),1/len(stk))
            ns=dict(zip(stk,nw)); allk=set(ns)|(set(held) if held else set())
            to=sum(abs(ns.get(k,0)-(held.get(k,0) if held else 0)) for k in allk); held=ns
        mt_tk=tkv[te]; mt_fwd=fwdm[te]
        if held:
            gv=wv=0.0
            for k,wk in held.items():
                h=np.where(mt_tk==k)[0]
                if len(h): gv+=wk*mt_fwd[h[0]]; wv+=wk
            g=gv/wv if wv>0 else np.nan
        else: g=np.nan
        rows.append((m,g-(to*0.0015 if decide else 0),bmm.get(m,np.nan)))
    return pd.DataFrame(rows,columns=["ym","sl_net","bm"]).dropna()
sl_conv=build("conv")

# book
L5=pd.read_csv(ROOT+"/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
L5["ym"]=L5["realized_ym"].astype(str).str[:7]; bk=L5[["ym","ret_L5_V5"]].dropna()

def ir(a): a=np.asarray(a); a=a[np.isfinite(a)]; return a.mean()/a.std()*np.sqrt(12) if a.std()>0 else np.nan

def analyze(sl, tag):
    d=sl.merge(bk,on="ym",how="inner").sort_values("ym").reset_index(drop=True)
    d["bk_act"]=d["ret_L5_V5"]-d["bm"]; d["sl_act"]=d["sl_net"]-d["bm"]
    # PIT 확장윈도 beta (≤t-1, 최소 24m) → 잔차
    resid=np.full(len(d),np.nan)
    for t in range(len(d)):
        if t<24: continue
        x=d["bk_act"].values[:t]; y=d["sl_act"].values[:t]  # t-1까지
        b=np.cov(x,y)[0,1]/np.var(x) if np.var(x)>0 else 0.0
        resid[t]=d["sl_act"].values[t]-b*d["bk_act"].values[t]
    d["resid"]=resid
    log(f"\n=== {tag} ===")
    for wlab,lo in [("full",None),("recent",2021)]:
        dd=d if lo is None else d[d["ym"]>=f"{lo}-01"]
        dd=dd.dropna(subset=["resid"])
        if len(dd)<12: log(f"  [{wlab}] n부족"); continue
        bIR=ir(dd["bk_act"]); sIR=ir(dd["sl_act"]); rIR=ir(dd["resid"])
        acorr=np.corrcoef(dd["bk_act"],dd["sl_act"])[0,1]
        rcorr=np.corrcoef(dd["bk_act"],dd["resid"])[0,1]
        resid_ann=dd["resid"].mean()*12
        # 직교 결합 이론치 + 실측 최적 λ
        theo=np.sqrt(bIR**2+max(rIR,0)**2)-bIR if rIR>0 else 0.0
        best=(-9,0)
        for lam in np.linspace(0,1.5,61):
            comb=dd["bk_act"].values+lam*dd["resid"].values
            di=ir(comb)-bIR
            if di>best[0]: best=(di,lam)
        log(f"  [{wlab}] n{len(dd)} book_IR {bIR:+.2f} | sleeve_IR {sIR:+.2f} (corr {acorr:+.2f}) | 잔차_IR {rIR:+.2f} (corr {rcorr:+.2f}) 잔차α {resid_ann*100:+.1f}%/yr")
        log(f"         직교ΔIR 이론 {theo:+.3f} | 실측 best ΔactiveIR {best[0]:+.3f} @λ{best[1]:.2f}  {'<-≥0.05 직교알파 실재' if best[0]>=0.05 else '<-<0.05 book-marginal 소진'}")
    return d

log("Round 10 — earnings sleeve를 book에 직교화 (PIT 확장윈도 beta). Round9 corr-블로커 공략.")
log("판정: recent 잔차 ΔactiveIR≥0.05 → 직교 earnings-alpha 실재 / <0.05 → earnings ⊂ book 소진.")
d_ew=analyze(sl_ew,"EW default (사전약정)")
d_conv=analyze(sl_conv,"conviction (robustness, sweep best t1.93)")

# blended 시리즈(book75/sleeve25 EW) 내보내기 → 계약 총-SR (governance surface용)
dd=sl_ew.merge(bk,on="ym",how="inner").sort_values("ym")
dd["blend"]=0.75*dd["ret_L5_V5"]+0.25*dd["sl_net"]
exp=dd[["ym","blend","bm"]].copy(); exp.columns=["ym","ret_net","benchmark_ret"]
exp.to_csv(OUT+"/round10_blend_series.csv",index=False)
log(f"\nblended(book75/sleeve25) → round10_blend_series.csv (n={len(exp)}) → 계약 총-SR 측정용(active-IR과 별개, governance surface)")
log("=== done ===")
