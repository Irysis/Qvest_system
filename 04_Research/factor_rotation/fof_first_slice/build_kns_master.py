"""build_kns_master.py — 전종목 KNS 실험용 master 패널 (factor-covered 전체, 2005-01..2026-06).
1회 빌드 후 모드별 필터(canonical/allclean/allliq)로 스코어링 재사용. float32 저장(메모리).
컬럼: ym, Ticker, [327 chars], F1, K200, KQ150, bad(admin|halt|unfaithful), adv.
벤치: clean benchmark.parquet(IKS200). 특성: factor_db 월별 Z_Score(pre-C13). 기존 327 fcols 정렬.
"""
import os, sys, numpy as np, pandas as pd, pyarrow.parquet as pq
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; os.environ.setdefault("QM_ROOT",R)
CACHE=R+"/.cache"; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
sys.path.insert(0,R+"/02_Infrastructure/discovery")
from discovery_explore import ensure_panel, HORIZONS_ALL
_p=ensure_panel(); excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
FCOLS=[c for c in _p.columns if c not in excl]; print(f"[chars] 327 특성셋 고정: {len(FCOLS)}",flush=True)

YMS=pd.period_range("2005-01","2026-06",freq="M").astype(str).tolist()
def ym2date(ym): return pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0)

print("[raw] RAWDATA 로드...",flush=True)
rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Ret","Close","Vol","K200","KQ150","AdminStock","TradingHalt","UnfaithfulDisc"]).to_pandas()
rd["Date"]=pd.to_datetime(rd["Date"]); rd["ym"]=rd.Date.dt.to_period("M").astype(str); rd=rd.sort_values(["Ticker","Date"])
rd["lr"]=np.log1p(rd["Ret"].clip(lower=-0.99)); rd["tval"]=rd.Close*rd.Vol
mret=rd.groupby(["Ticker","ym"],sort=True).agg(lr=("lr","sum"),K200=("K200","last"),KQ150=("KQ150","last"),
    Admin=("AdminStock","last"),Halt=("TradingHalt","last"),Unf=("UnfaithfulDisc","last"),
    adv=("tval","mean"),nret=("Ret","count")).reset_index()
mret["mret"]=np.expm1(mret["lr"]); mret=mret.sort_values(["Ticker","ym"]); mret["F1"]=mret.groupby("Ticker")["mret"].shift(-1)
days=rd.groupby("ym")["Date"].nunique(); med_days=int(days.median()); last_ym=days.index.max()
if days.loc[last_ym] < 0.6*med_days: mret.loc[mret.ym=="2026-06","F1"]=np.nan
mret["bad"]=(mret.Admin.fillna(0).astype(float)>0)|(mret.Halt.fillna(0).astype(float)>0)|(mret.Unf.fillna(0).astype(float)>0)
mret["K200f"]=mret.K200.fillna(0).astype(float)>0; mret["KQ150f"]=mret.KQ150.fillna(0).astype(float)>0
# 방어적 winsor forward수익
mret["F1"]=mret["F1"].clip(-0.95,3.0)
# clean 벤치
bpq=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bcol=[c for c in("BM_Ret","Ret") if c in bpq.columns][0]
bpq["Date"]=pd.to_datetime(bpq["Date"]); bpq["ym"]=bpq.Date.dt.to_period("M").astype(str)
bpq=bpq.dropna(subset=[bcol]); bpq=bpq[np.isfinite(bpq[bcol])&(bpq[bcol].abs()<0.5)]
bm=bpq.groupby("ym").agg(bmlr=(bcol,lambda s:np.log1p(s).sum())).reset_index(); bm["bm_m"]=np.expm1(bm.bmlr); bm=bm.sort_values("ym"); bm["BMf"]=bm.bm_m.shift(-1)
if days.loc[last_ym]<0.6*med_days: bm.loc[bm.ym=="2026-06","BMf"]=np.nan
bm[["ym","BMf"]].dropna().assign(Date=lambda d:d.ym.map(ym2date)).rename(columns={"BMf":"BM_Ret"})[["Date","BM_Ret"]].to_parquet(OUT+"/kns_master_bench.parquet",index=False)
print(f"[bench] clean IKS200 | bm_m∈[{bm.bm_m.min():.3f},{bm.bm_m.max():.3f}]",flush=True)

# 월별 factor_db pivot → 327 wide (전 cov=T 종목)
rows=[]; miss=[]
meta=mret[["Ticker","ym","F1","K200f","KQ150f","bad","adv","nret"]]
for i,ym in enumerate(YMS):
    fp=CACHE+f"/factor_db/factor_db_{ym.replace('-','')}.parquet"
    if not os.path.exists(fp): miss.append(ym); continue
    fdb=pq.read_table(fp,columns=["Ticker","Factor_Name","Z_Score","Coverage"]).to_pandas()
    fdb=fdb[(fdb.Coverage==True)&(fdb.Z_Score.notna())]
    wide=fdb.pivot_table(index="Ticker",columns="Factor_Name",values="Z_Score",aggfunc="first").reindex(columns=FCOLS)
    mm=meta[meta.ym==ym].drop(columns=["ym"]).set_index("Ticker")
    df=wide.join(mm,how="inner").reset_index(); df.insert(0,"ym",ym); rows.append(df)
    if i%48==0: print(f"  [build] {ym} ({i}/{len(YMS)})",flush=True)
panel=pd.concat(rows,ignore_index=True)
# float32 특성 (메모리)
for c in FCOLS: panel[c]=panel[c].astype("float32")
gsz=panel.groupby("ym").size()
print(f"[master] {panel.shape} | 월수 {panel.ym.nunique()} | 종목/월 median {int(gsz.median())} (2026-06={gsz.get('2026-06')})",flush=True)
if miss: print(f"[warn] factor_db 결측월 {len(miss)}: {miss[:5]}",flush=True)
panel.to_parquet(OUT+"/kns_master_panel.parquet",index=False)
print("saved kns_master_panel.parquet + kns_master_bench.parquet",flush=True)
