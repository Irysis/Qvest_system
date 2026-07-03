# Phase 0 발굴 모델 — pre-C13 327팩터의 비선형 OOS 신호 (discovery≠production, P7)
#   A(baseline) = score_eff (생산 정렬-선형 신호)
#   B(discovery)= HGB([score_eff + 327 pre-C13 factors] -> fwd_ret)  ← score_eff 위에 raw 얹음
#   C(factors-only)= HGB([327 factors] -> fwd_ret)                    ← raw 단독
#   walk-forward 분기 재학습, burn-in 60m. 강정규화(반-DPL-과적합).
#   타깃 = 월내 횡단면 z(fwd_ret) (시장성분 제거, 랭킹 집중).
#   모델 = sklearn HistGradientBoostingRegressor (LightGBM 부재 대체, 동등).
#   ★ 산출(disc score)은 발굴 전용 — R 검수 게이트(canonical_screen_bt) 통과 전 자본 금지.
import pandas as pd, numpy as np, sys, os
from sklearn.ensemble import HistGradientBoostingRegressor as HGB

ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT=ROOT+"/.cache/discovery"
PANEL=sys.argv[1] if len(sys.argv)>1 else OUT+"/phase0_panel_2005-01_2026-04.parquet"
BURNIN=int(os.environ.get("BURNIN","60")); RETRAIN=int(os.environ.get("RETRAIN","3"))

df=pd.read_parquet(PANEL)
fcols=[c for c in df.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]
df[fcols]=df[fcols].fillna(0.0)             # Z 결측 = 횡단면평균(0)
df=df.dropna(subset=["fwd_ret_1m","score_eff"]).reset_index(drop=True)
df["y"]=df.groupby("ym")["fwd_ret_1m"].transform(lambda s:(s-s.mean())/(s.std()+1e-9))
months=sorted(df["ym"].unique()); oos=months[BURNIN:]
print(f"panel {df.shape} | months {len(months)} | OOS {oos[0]}~{oos[-1]} ({len(oos)})")

HGBP=dict(max_iter=300, learning_rate=0.03, max_leaf_nodes=15, max_depth=4,
          min_samples_leaf=80, l2_regularization=5.0, max_features=0.6,
          early_stopping=False, random_state=42)

rows=[]; mB=mC=None
for i,ym in enumerate(oos):
    if i % RETRAIN == 0:
        tr=df[df["ym"]<ym]
        mB=HGB(**HGBP).fit(tr[["score_eff"]+fcols].values, tr["y"].values)
        mC=HGB(**HGBP).fit(tr[fcols].values, tr["y"].values)
    te=df[df["ym"]==ym].copy()
    te["predB"]=mB.predict(te[["score_eff"]+fcols].values)
    te["predC"]=mC.predict(te[fcols].values)
    rows.append(te[["ym","Ticker","score_eff","fwd_ret_1m","predB","predC"]])
res=pd.concat(rows, ignore_index=True)

def ic_series(sigcol):
    return res.groupby("ym").apply(lambda d: d[sigcol].corr(d["fwd_ret_1m"],method="spearman")).dropna()
def rep(nm,s):
    t=s.mean()/s.std()*np.sqrt(len(s)); print(f"  {nm:24s} IC {s.mean():+.4f}  t {t:+.2f}  hit {np.mean(s>0):.2f}")
print("\n=== OOS 월별 랭크-IC (vs forward 1M) ===")
rep("A score_eff(baseline)", ic_series("score_eff"))
rep("B score_eff+factors", ic_series("predB"))
rep("C factors-only", ic_series("predC"))

def top_fwd(sigcol,n=20):
    return res.groupby("ym").apply(lambda d: d.nlargest(n,sigcol)["fwd_ret_1m"].mean()).dropna()
print("\n=== long-only top-20 월평균 forward (proxy, net 아님) ===")
for nm,col in [("A score_eff","score_eff"),("B score_eff+factors","predB"),("C factors-only","predC")]:
    s=top_fwd(col); t=s.mean()/s.std()*np.sqrt(len(s))
    print(f"  {nm:24s} {s.mean()*100:+.3f}%/m  t {t:+.2f}")

of=OUT+"/phase0_scores.parquet"; res.to_parquet(of,index=False)
print("\nsaved:",of," (발굴 전용 — R 게이트 전 자본 금지)")
