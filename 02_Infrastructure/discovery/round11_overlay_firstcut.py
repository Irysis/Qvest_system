# Round 11 — 피벗: earnings-revision BREADTH를 *셀렉션 아닌 시장 타이밍 오버레이*로 (첫 게이트)
#   selection 천장(Round9/10 완결 falsify) 회피 — book의 실제 레버(overlay)에 새 입력(earnings breadth).
#   가설: 유니버스 집계 earnings-revision breadth(t-1)가 다음달 시장(KOSPI200) 방향을 타이밍하나?
#   첫 게이트(cheap): ① breadth→market IC ② 단순 risk-on/off SR vs buy-hold ③ book 위 stack ΔSR.
#     죽으면 overlay 아이디어 cheap-kill. 살면 book 통합 정밀(Round12).
#   PIT: breadth_{t-1}로 t 포지션. 패널 팩터=sig_date 정렬(Phase0 검증). 엄격 인과.
import pandas as pd, numpy as np, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/round11_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")

pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
EARN=[f for f in ["C04_ESBR","C05_ESCR","C02_EPS_Chg_1m","C06_TP_Gap"] if f in pan.columns]
# breadth: 월별 유니버스 평균 earnings-revision z (sig_date에 알 수 있음) + 양수비율
pan["e_mean"]=pan[EARN].mean(axis=1)
br=pan.groupby("ym").agg(breadth_z=("e_mean","mean"), breadth_pos=("e_mean",lambda s:(s>0).mean())).reset_index()
# bm 월간 총수익 (forward: t월 수익)
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmm=bm.groupby("ym")[bc].apply(lambda r:np.expm1(np.log1p(r).sum())).reset_index().rename(columns={bc:"mkt"})
d=br.merge(bmm,on="ym",how="inner").sort_values("ym").reset_index(drop=True)
# t-1 breadth (엄격 인과) + 확장윈도 z (PIT: ≤t-1 평균/표준편차)
d["bz_lag"]=d["breadth_z"].shift(1); d["bp_lag"]=d["breadth_pos"].shift(1)
ez=np.full(len(d),np.nan)
for t in range(13,len(d)):
    h=d["bz_lag"].values[1:t+1]; h=h[np.isfinite(h)]
    if len(h)>=12: ez[t]=(d["bz_lag"].values[t]-h.mean())/(h.std()+1e-9)
d["bz_z"]=ez
OOS=d[d["ym"]>="2010-01"].dropna(subset=["bz_lag","mkt"]).reset_index(drop=True)

def ic(x,y):
    m=np.isfinite(x)&np.isfinite(y);
    return np.corrcoef(x[m],y[m])[0,1] if m.sum()>5 else np.nan
def sr(r): r=np.asarray(r); r=r[np.isfinite(r)]; return r.mean()/r.std()*np.sqrt(12) if r.std()>0 else np.nan

log("=== Round 11 earnings-breadth 시장타이밍 오버레이 첫 게이트 ===")
log(f"EARN={EARN} | n_OOS={len(OOS)} ({OOS['ym'].iloc[0]}~{OOS['ym'].iloc[-1]})")

log("\n① breadth(t-1) → 다음달 시장 IC (Pearson/Spearman)")
for tag,lo,hi in [("full","2010-01","2026-12"),("recent","2021-01","2026-12")]:
    s=OOS[(OOS["ym"]>=lo)&(OOS["ym"]<=hi)]
    p=ic(s["bz_lag"].values,s["mkt"].values); pz=ic(s["bz_z"].values,s["mkt"].values)
    sp=ic(pd.Series(s["bz_lag"]).rank().values, pd.Series(s["mkt"]).rank().values)
    log(f"  [{tag}] n{len(s)} raw-IC {p:+.3f} | exp-z IC {pz:+.3f} | Spearman {sp:+.3f}")

log("\n② 단순 risk-on/off (breadth-z>0 → 시장100%, else 현금0%) vs buy-hold")
for tag,lo in [("full","2010-01"),("recent","2021-01")]:
    s=OOS[OOS["ym"]>=lo].copy()
    s["pos"]=(s["bz_z"]>0).astype(float)   # t-1 z>0 이면 t월 시장보유
    s["ov"]=s["pos"]*s["mkt"]
    bh=sr(s["mkt"]); ov=sr(s["ov"]); act=s["ov"]-s["mkt"]
    expo=s["pos"].mean()
    log(f"  [{tag}] buy-hold SR {bh:+.2f} | overlay SR {ov:+.2f} (노출 {expo*100:.0f}%) | 활성 SR {sr(act):+.2f} cum활성 {act.sum()*100:+.1f}%")

log("\n③ 연속노출 (z를 [0,1] 매핑: 0.5+0.5*tanh(z)) vs buy-hold")
for tag,lo in [("full","2010-01"),("recent","2021-01")]:
    s=OOS[OOS["ym"]>=lo].copy()
    s["pos"]=0.5+0.5*np.tanh(s["bz_z"].fillna(0)); s["ov"]=s["pos"]*s["mkt"]
    log(f"  [{tag}] overlay SR {sr(s['ov']):+.2f} (평균노출 {s['pos'].mean()*100:.0f}%) | 활성 cum {(s['ov']-s['mkt']).sum()*100:+.1f}%")

log("\n판정: recent IC|>0.10 & overlay 활성 SR>0 & 노출 적당 → breadth 타이밍 실재 → book 통합 Round12.")
log("      IC~0 또는 활성 SR<0 → earnings-breadth 시장타이밍 무신호 → 이 오버레이 방법론 cheap-kill.")
log("=== done ===")
