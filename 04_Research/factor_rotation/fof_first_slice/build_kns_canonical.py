"""build_kns_canonical.py — KNS 분석용 통합 패널 2005-01..2026-06 (헌법 canonical 유니버스).
score_eff(2026-04 종료) 대신 RAWDATA K200∪KQ150 월말 멤버십 = KOSPI200∪KQ150 (헌법 Universe).
특성 = factor_db 월별 pre-C13 Z_Score(기존 panel 327 fcols 정렬). PIT: factor_db_{ym}=ym말 스냅샷.
계약 입력(canonical_screen_bt 규약): returns_dt.Ret_1m@D=forward 실현(D+1월), bench_dt.BM_Ret@D=forward, liq_dt.adv@D=D시점 거래대금.
산출: kns_canonical_panel.parquet(ym,Ticker,327 chars,F1) + kns_returns.parquet + kns_bench.parquet + kns_liq.parquet
"""
import os, sys, numpy as np, pandas as pd, pyarrow.parquet as pq
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; os.environ.setdefault("QM_ROOT",R)
CACHE=R+"/.cache"; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
sys.path.insert(0,R+"/02_Infrastructure/discovery")
from discovery_explore import ensure_panel, HORIZONS_ALL
# 기존 327 특성셋 (동일 substrate 유지)
_p=ensure_panel(); excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
FCOLS=[c for c in _p.columns if c not in excl]; print(f"[chars] 기존 327 특성셋 고정: {len(FCOLS)}")

START,END="2005-01","2026-06"
def month_list(s,e): return pd.period_range(s,e,freq="M").astype(str).tolist()
YMS=month_list(START,END)

# ── RAWDATA 일별 → 월별 멤버십/수익/거래대금 ──
print("[raw] RAWDATA 로드...")
rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Ret","Close","Vol","K200","KQ150","BM_Ret"]).to_pandas()
rd["Date"]=pd.to_datetime(rd["Date"]); rd["ym"]=rd.Date.dt.to_period("M").astype(str)
rd=rd.sort_values(["Ticker","Date"])
# 월별 종목 복리수익
rd["lr"]=np.log1p(rd["Ret"].clip(lower=-0.99))
mret=rd.groupby(["Ticker","ym"],sort=True).agg(lr=("lr","sum"),
      K200=("K200","last"),KQ150=("KQ150","last"),
      tval=("Close", lambda s: np.nan)).reset_index()  # tval placeholder; compute below properly
# 거래대금(월내 일별 Close*Vol 평균) — 근사 20일 평균거래대금
rd["tval_d"]=rd["Close"]*rd["Vol"]
adv=rd.groupby(["Ticker","ym"])["tval_d"].mean().reset_index().rename(columns={"tval_d":"adv"})
mret=mret.drop(columns=["tval"]).merge(adv,on=["Ticker","ym"],how="left")
mret["mret"]=np.expm1(mret["lr"])
# 완전월 판정: 각 ym의 거래일수 (마지막 월 부분월 감별)
days=rd.groupby("ym")["Date"].nunique(); med_days=int(days.median())
mret["univ"]=(mret.K200.fillna(0).astype(float)>0)|(mret.KQ150.fillna(0).astype(float)>0)
# forward 1M 실현수익
mret=mret.sort_values(["Ticker","ym"])
mret["F1"]=mret.groupby("Ticker")["mret"].shift(-1)
# 부분월(마지막) forward 무효화: 2026-07 부분월이면 2026-06 F1(=7월) 불완전 → NaN
last_ym=days.index.max()
if days.loc[last_ym] < 0.6*med_days:
    prev=YMS  # 2026-06 F1 = 2026-07(부분) → 무효
    mret.loc[mret.ym=="2026-06","F1"]=np.nan
    print(f"[warn] 마지막월 {last_ym} 부분월({days.loc[last_ym]}<{med_days}거래일) → 2026-06 F1(7월)=NaN (holdings-only)")
# 벤치: clean benchmark.parquet(IKS200 수정본, 일별 BM_Ret [-0.12,0.12]) — RAWDATA BM_Ret 컬럼은 손상(5.81 오류값)
bpq=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bcol=[c for c in("BM_Ret","Ret") if c in bpq.columns][0]
bpq["Date"]=pd.to_datetime(bpq["Date"]); bpq["ym"]=bpq.Date.dt.to_period("M").astype(str)
bpq=bpq.dropna(subset=[bcol]); bpq=bpq[np.isfinite(bpq[bcol])&(bpq[bcol].abs()<0.5)]   # 방어적 클린
bm=bpq.groupby("ym").agg(bmlr=(bcol,lambda s:np.log1p(s).sum())).reset_index()
bm["bm_m"]=np.expm1(bm["bmlr"]); bm=bm.sort_values("ym"); bm["BMf"]=bm["bm_m"].shift(-1)
if days.loc[last_ym] < 0.6*med_days: bm.loc[bm.ym=="2026-06","BMf"]=np.nan
bmmap=dict(zip(bm.ym,bm.BMf))
print(f"[bench] clean benchmark.parquet 경유 | 월범위 {bm.ym.min()}..{bm.ym.max()} | bm_m∈[{bm.bm_m.min():.3f},{bm.bm_m.max():.3f}]")
print(f"[raw] 월별 종목 {mret.Ticker.nunique()} | univ월수 {mret[mret.univ].ym.nunique()} | median거래일 {med_days}")

# ── 월별 factor_db pivot → 327 특성 wide, univ ∩ 특성보유 ──
def ym2date(ym): return (pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0))
rows=[]; miss=[]
for ym in YMS:
    fp=CACHE+f"/factor_db/factor_db_{ym.replace('-','')}.parquet"
    if not os.path.exists(fp): miss.append(ym); continue
    fdb=pq.read_table(fp,columns=["Ticker","Factor_Name","Z_Score","Coverage"]).to_pandas()
    fdb=fdb[(fdb.Coverage==True)&(fdb.Z_Score.notna())]
    wide=fdb.pivot_table(index="Ticker",columns="Factor_Name",values="Z_Score",aggfunc="first")
    wide=wide.reindex(columns=FCOLS)  # 327 정렬 (없는 특성=NaN)
    u=mret[(mret.ym==ym)&(mret.univ)][["Ticker","F1"]].set_index("Ticker")
    df=wide.join(u,how="inner").reset_index()   # univ ∩ 특성보유
    df.insert(0,"ym",ym); rows.append(df)
panel=pd.concat(rows,ignore_index=True)
if miss: print(f"[warn] factor_db 결측월 {len(miss)}: {miss[:5]}...")
gsz=panel.groupby("ym").size()
print(f"[panel] {panel.shape} | 월수 {panel.ym.nunique()} ({panel.ym.min()}..{panel.ym.max()}) | 종목/월 median {int(gsz.median())} (2005={gsz.get('2005-01')}, 2026-06={gsz.get('2026-06')})")
finite=np.isfinite(panel[FCOLS].values).mean(); print(f"[panel] 특성 finite 비율 {finite:.3f}")
panel.to_parquet(OUT+"/kns_canonical_panel.parquet",index=False)

# ── 계약 입력: returns_dt/bench_dt/liq_dt (Date=월말, forward 규약) ──
# ret은 univ-at-signal 종목만(스코어 존재 종목) + 방어적 winsorize(±: [-0.95,3.0], 정크티커/데이터오류 컷)
rr=mret[mret.univ][["Ticker","ym","F1"]].dropna(subset=["F1"]).copy()
n_out=int((rr.F1>3.0).sum()); rr["F1"]=rr["F1"].clip(-0.95,3.0)
rr["Date"]=rr.ym.map(ym2date); ret_dt=rr[["Date","Ticker","F1"]].rename(columns={"F1":"Ret_1m"})
print(f"[ret] univ-only forward수익 {len(ret_dt)} | winsor >300% clipped {n_out}건")
ret_dt.to_parquet(OUT+"/kns_returns.parquet",index=False)
bd=pd.DataFrame({"ym":list(bmmap.keys())}); bd["BM_Ret"]=bd.ym.map(bmmap); bd=bd.dropna(subset=["BM_Ret"])
bd["Date"]=bd.ym.map(ym2date); bd[["Date","BM_Ret"]].to_parquet(OUT+"/kns_bench.parquet",index=False)
ld=mret[["Ticker","ym","adv"]].dropna(subset=["adv"]).copy(); ld["Date"]=ld.ym.map(ym2date)
ld[["Date","Ticker","adv"]].to_parquet(OUT+"/kns_liq.parquet",index=False)
print(f"[contract] returns {len(ret_dt)}(→{ret_dt.Date.max().date()}) | bench {len(bd)} | liq {len(ld)}")
print("saved kns_canonical_panel + kns_returns/bench/liq.parquet")
