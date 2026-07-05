"""build_insider_signal.py — DART 임원 순매수 신호 패널 + (커버리지 충분 시) 정본 백테.
백필(dart_insider_backfill.R) 완료 시 즉시 실행. 내부자 CSV(백필 체크포인트) + insider_trades_clean.parquet 통합
→ 임원(등기임원) 순매수 신호(월별 종목) → forward IC + top-25 long-only 포트(K200∪KQ150).
≥60개월 커버리지면 canonical_screen_bt(R) 정본 백테로 넘길 scores 저장.
발견: 임원 분리 시 ICIR 1.31@H1(주요주주 음수). K200∪KQ150 한정. return 파생 아닌 비-return frontier.
"""
import os, sys, glob, numpy as np, pandas as pd, pyarrow.parquet as pq
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT=R+"/04_Research/insider"; os.makedirs(OUT,exist_ok=True)
def num(x):
    s=str(x).replace(",","").strip()
    if s in("-","","nan","None","NA"): return np.nan
    try: return float(s)
    except: return np.nan

# 1) 통합: 백필 체크포인트 CSV(rows>0) + 기존 clean parquet
frames=[]
clean=R+"/.cache/dart/insider_trades_clean.parquet"
if os.path.exists(clean): frames.append(pd.read_parquet(clean))
for f in sorted(glob.glob(R+"/.cache/dart/insider_backfill/*.csv")):
    try:
        d=pd.read_csv(f,dtype=str)
        if "sp_stock_lmp_irds_cnt" in d.columns and len(d)>0: frames.append(d)
    except: pass
ins=pd.concat(frames,ignore_index=True).drop_duplicates(subset=["rcept_no","repror","Ticker"] if "rcept_no" in frames[0].columns else None)
ins["irds"]=ins["sp_stock_lmp_irds_cnt"].map(num)
ins["Date"]=pd.to_datetime(ins["Date"],errors="coerce"); ins=ins.dropna(subset=["Date","irds","Ticker"])
ins["ym"]=ins.Date.dt.to_period("M").astype(str)
ins["is_exec"]=(ins["isu_exctv_ofcps"].astype(str).str.len()>1)   # 직위 보유 = 임원
ins["irds_w"]=ins.groupby("Ticker")["irds"].transform(lambda s:s.clip(s.quantile(.02),s.quantile(.98)))
ex=ins[ins.is_exec].groupby(["Ticker","ym"]).irds_w.sum().reset_index().rename(columns={"irds_w":"exec_net"})
print(f"[insider] 통합 {len(ins)}건 | 임원신호 {len(ex)} 종목-월 | 월 {ex.ym.nunique()} ({ex.ym.min()}~{ex.ym.max()})")

# 2) forward 수익 + 유니버스 (RAWDATA)
rd=pq.read_table(R+"/.cache/RAWDATA.parquet",columns=["Date","Ticker","Ret","K200","KQ150"]).to_pandas()
rd["Date"]=pd.to_datetime(rd["Date"]); rd["ym"]=rd.Date.dt.to_period("M").astype(str); rd["lr"]=np.log1p(rd.Ret.clip(-0.99))
m=rd.groupby(["Ticker","ym"]).agg(lr=("lr","sum"),K200=("K200","last"),KQ150=("KQ150","last")).reset_index().sort_values(["Ticker","ym"])
m["mret"]=np.expm1(m.lr); m["F1"]=m.groupby("Ticker")["mret"].shift(-1)
m["univ"]=(m.K200.fillna(0)>0)|(m.KQ150.fillna(0)>0)
j=ex.merge(m[m.univ][["Ticker","ym","F1"]],on=["Ticker","ym"],how="inner").dropna(subset=["F1"])
# 신호 = 임원 순매수 있는 종목만(이벤트). 부호+크기.
sig=j[j.exec_net!=0].copy()
def date_of(ym): return (pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0))
sig["Date"]=sig.ym.map(date_of)
sig[["Date","Ticker","exec_net"]].rename(columns={"exec_net":"score"}).to_parquet(OUT+"/scores_insider_exec.parquet",index=False)

# 3) 진단: forward IC + crude 포트
ics=[]
for ym,g in sig.groupby("ym"):
    if len(g)<8 and g.exec_net.std()>0: continue
    if g.exec_net.std()>0: ics.append(np.corrcoef(g.exec_net.rank(),g.F1.rank())[0,1])
ics=np.array(ics)
nmo=sig.ym.nunique()
print(f"[진단] 임원신호 월별 rank-IC mean {ics.mean():+.4f} ICIR {ics.mean()/ics.std()*np.sqrt(12):+.2f} (n={len(ics)})")
print(f"[상태] 커버리지 {nmo}월 → {'canonical_screen_bt 정본 백테 가능(≥60월)' if nmo>=60 else '백필 계속 필요(현재 <60월, 정본 백테 대기)'}")
print(f"saved scores_insider_exec.parquet ({len(sig)} 종목-월)")
