# Round 4 — horizon IC 스캔 (마지막 직교축: 보유기간)
#   327팩터 × {1,3,6,12M} forward, 최근(2021-26) vs 전기간 횡단면 IC.
#   가설: 감쇠가 horizon 의존(자사주 1M死·12M+) → 어떤 팩터가 어떤 H서 최근 예측력?
#   max 최근 IC noise(~0.02)면 소진 확정. 0.05+ 면 리드.
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings("ignore")
import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/round4_horizon_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")

pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in pan.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]
pan[fcols]=pan[fcols].fillna(0.0)
# 월간 수익 + fwd_H (RAWDATA)
rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Ret"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd=rd.dropna(subset=["Ret"])
rd["lr"]=np.log1p(rd["Ret"].clip(-0.99))
mret=rd.groupby(["Ticker","ym"])["lr"].sum().reset_index(); mret["mret"]=np.expm1(mret["lr"])
mret=mret.sort_values(["Ticker","ym"])
# forward H개월 로그수익 합 (t+1..t+H)
def fwdH(s,H):
    arr=s.values; out=np.full(len(arr),np.nan)
    for i in range(len(arr)):
        if i+H<len(arr): out[i]=arr[i+1:i+1+H].sum()
    return out
for H in (1,3,6,12):
    mret[f"F{H}"]=mret.groupby("Ticker")["lr"].transform(lambda s: pd.Series(fwdH(s,H),index=s.index))
    mret[f"F{H}"]=np.expm1(mret[f"F{H}"])
fwdcols=[f"F{H}" for H in (1,3,6,12)]
m2=mret[["Ticker","ym"]+fwdcols]
df=pan.merge(m2,on=["Ticker","ym"],how="left")

def ic_scan(period_lo=None,period_hi=None):
    d=df if period_lo is None else df[(df["ym"]>=period_lo)&(df["ym"]<=period_hi)]
    res={}
    for H in (1,3,6,12):
        fc=f"F{H}"; dd=d.dropna(subset=[fc])
        ics={}
        # score_eff
        ics["score_eff"]=dd.groupby("ym").apply(lambda g: g["score_eff"].corr(g[fc],method="spearman")).mean()
        for f in fcols:
            ics[f]=dd.groupby("ym").apply(lambda g: g[f].corr(g[fc],method="spearman")).mean()
        res[H]=pd.Series(ics)
    return res

log("=== Round 4 horizon IC 스캔 ===")
for tag,lo,hi in [("전기간",None,None),("최근 2021-26","2021-01","2026-04")]:
    log(f"\n## {tag}")
    R=ic_scan(lo,hi)
    for H in (1,3,6,12):
        s=R[H].dropna().sort_values(key=lambda x:x.abs(),ascending=False)
        se=R[H].get("score_eff",np.nan)
        top=s.head(6)
        log(f"  F{H:>2}M: score_eff IC {se:+.4f} | maxabs {s.iloc[0]:+.4f}({s.index[0]}) | top: "+
            ", ".join(f"{k} {v:+.3f}" for k,v in top.items()))
log("\n판정: 최근 maxabs IC가 ~0.02(noise)면 horizon축도 소진 → 횡단면 selection 알파 confident 소진.")
log("=== done ===")
