# Phase 0 조립기 — 발굴 모델 입력 패널 구성 (discovery≠production, P7)
#   features = pre-C13 factor_db Z_Score (wide, 정렬 이전) + base = score_eff(warm-start)
#   target = forward 1M return (RAWDATA 복리, Ret_1m 미사용 — trailing 신뢰불가)
#   PIT: factor_db_{ym}=ym말 스냅샷, score_eff(ym), fwd_ret=ym+1 → 누수 없음.
#   ★ 산출은 발굴 전용(자본 게이트 미경유). pyarrow 사용(R-arrow 우회).
import pyarrow.parquet as pq
import pandas as pd, numpy as np, os, sys

ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"; os.makedirs(OUT, exist_ok=True)
ASC=ROOT+"/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"

START=sys.argv[1] if len(sys.argv)>1 else "2010-01"
END  =sys.argv[2] if len(sys.argv)>2 else "2010-12"
VALUE="Z_Score"   # pre-C13 횡단면 표준화값 (정렬 이전)

def months(s,e): return pd.date_range(s+"-01", e+"-01", freq="MS").strftime("%Y-%m").tolist()

# 1. score_eff (universe + warm-start base)
sc=pq.read_table(ASC, columns=["Date","Ticker","score_eff"]).to_pandas()
sc["ym"]=pd.to_datetime(sc["Date"]).dt.strftime("%Y-%m")
sc=sc[["ym","Ticker","score_eff"]].dropna(subset=["score_eff"])

# 2. forward 1M return (RAWDATA 복리)
rd=pq.read_table(CACHE+"/RAWDATA.parquet", columns=["Date","Ticker","Ret"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m")
rd=rd.dropna(subset=["Ret"]); rd["lr"]=np.log1p(rd["Ret"].clip(lower=-0.99))
mret=rd.groupby(["Ticker","ym"],sort=True)["lr"].sum().reset_index()
mret["mret"]=np.expm1(mret["lr"])
mret=mret.sort_values(["Ticker","ym"])
mret["fwd_ret_1m"]=mret.groupby("Ticker")["mret"].shift(-1)   # 다음달 = forward
fwd=mret[["Ticker","ym","fwd_ret_1m"]]

# 3. 월별 루프: pre-C13 factor wide + join
panels=[]
for ym in months(START,END):
    fp=CACHE+f"/factor_db/factor_db_{ym.replace('-','')}.parquet"
    if not os.path.exists(fp): continue
    fdb=pq.read_table(fp, columns=["Ticker","Factor_Name",VALUE,"Coverage"]).to_pandas()
    fdb=fdb[(fdb["Coverage"]==True)&(fdb[VALUE].notna())]
    wide=fdb.pivot_table(index="Ticker", columns="Factor_Name", values=VALUE, aggfunc="first").reset_index()
    base=sc[sc["ym"]==ym][["Ticker","score_eff"]]
    fr=fwd[fwd["ym"]==ym][["Ticker","fwd_ret_1m"]]
    df=base.merge(fr,on="Ticker",how="inner").merge(wide,on="Ticker",how="left")
    df.insert(0,"ym",ym); panels.append(df)

panel=pd.concat(panels, ignore_index=True)
fcols=[c for c in panel.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]
print("PANEL:", panel.shape, "| months", panel["ym"].nunique(), "| factor cols", len(fcols))
print("score_eff non-null:", round(panel["score_eff"].notna().mean(),3),
      "| fwd_ret non-null:", round(panel["fwd_ret_1m"].notna().mean(),3))
g=panel.groupby("ym").size(); print("rows/month: min",g.min(),"median",int(g.median()),"max",g.max())

# ★ PIT 정렬 sanity: score_eff ↔ fwd_ret 월별 횡단면 Spearman IC (양수여야 정렬 정상)
def xs_ic(d):
    d=d.dropna(subset=["score_eff","fwd_ret_1m"])
    if len(d)<20: return np.nan
    return d["score_eff"].corr(d["fwd_ret_1m"], method="spearman")
ics=panel.groupby("ym").apply(xs_ic).dropna()
print(f"\n★ score_eff↔fwd_ret 월별IC: mean {ics.mean():+.4f} | t {ics.mean()/ics.std()*np.sqrt(len(ics)):+.2f} | hit {np.mean(ics>0):.2f} (양수=정렬OK)")

of=OUT+f"/phase0_panel_{START}_{END}.parquet"
panel.to_parquet(of, index=False)
print("saved:", of)
