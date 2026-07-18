"""WT-D20260718_003 — Orthogonality of XATTN vs incumbent + estimators (angle ② core test).
(1) Cross-sectional score rank-corr: XATTN_ENS vs KNS_L2 / IPCA_K4 / E2E per month -> mean.
(2) Return-level book-marginal: cor(XATTN_ENS active, incumbent L5_V2 active) + fixed-weight blend dIR (diagnostic).
All-local. metric_type labels. NOT a weight proposal (fixed-w = orthogonality diagnostic per measurement-graduation §4)."""
import pandas as pd, numpy as np
from scipy.stats import spearmanr
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT=R+"/04_Research/factor_rotation/fof_first_slice/"; STG=R+"/stage_artifacts/WT_D20260718_003/"

def load(f):
    d=pd.read_parquet(OUT+f); d["ym"]=pd.to_datetime(d.Date).dt.to_period("M").astype(str); return d
xa=load("scores_XATTN_canonical_ENS.parquet")
est={"KNS_L2":load("kns_scores_L2_canonical.parquet"),
     "IPCA_K4":load("scores_IPCA_canonical_K4.parquet"),
     "E2E":load("scores_E2E_canonical.parquet")}

print("=== (1) CROSS-SECTIONAL SCORE rank-corr: XATTN_ENS vs estimator (per-month Spearman, mean) ===")
score_corr={}
for nm,e in est.items():
    cors=[]
    for ym,gx in xa.groupby("ym"):
        ge=e[e.ym==ym]
        m=gx.set_index("Ticker")["score"].to_frame("x").join(ge.set_index("Ticker")["score"].to_frame("y"),how="inner").dropna()
        if len(m)>25 and m.x.std()>1e-9 and m.y.std()>1e-9:
            cors.append(spearmanr(m.x,m.y).correlation)
    cors=np.array([c for c in cors if np.isfinite(c)])
    score_corr[nm]=float(np.mean(cors))
    print(f"  XATTN vs {nm}: mean rank-corr = {np.mean(cors):+.3f}  (median {np.median(cors):+.3f}, n={len(cors)} months)")

print("\n=== (2) RETURN-LEVEL book-marginal vs incumbent (STR_1715 M4 R05 noLayer4) ===")
# XATTN ENS active returns (from R canonical screen, liq 2e8)
xr=pd.read_csv(STG+"xattn_ens_active_returns.csv")
xr["ym"]=pd.to_datetime(xr.date).dt.to_period("M").astype(str)
# incumbent book: period_returns_layer5 ret_L5_V2 with bm proxy = book - active? we have ret_L5_V2 (book net) and need bm.
bk=pd.read_csv(R+"/04_Research/pg2_forensics/v24_book_remeasure/period_returns_layer5.csv")
bk=bk[["realized_ym","ret_L5_V2"]].rename(columns={"realized_ym":"ym","ret_L5_V2":"book"}).dropna()
# bench: kns_master_bench (cap-w K200) monthly, align by ym
bn=pd.read_parquet(OUT+"kns_master_bench.parquet"); bn["ym"]=pd.to_datetime(bn.Date).dt.to_period("M").astype(str)
bn=bn[["ym","BM_Ret"]].dropna()
M=xr[["ym","ret_net","benchmark_ret","act"]].rename(columns={"act":"xa_act","ret_net":"xa_net"})
M=M.merge(bk,on="ym",how="inner").merge(bn,on="ym",how="inner").sort_values("ym").reset_index(drop=True)
M["book_act"]=M["book"]-M["BM_Ret"]
print(f"  common months n={len(M)}  {M.ym.min()}..{M.ym.max()}")

# offset audit (book misalignment guard): cor(book_act, xa_act) at shifts -3..+3
print("  offset audit cor(book_act, xa_act) shift -3..+3 (peak expected at 0 if aligned):")
for k in range(-3,4):
    b=M["book_act"].shift(k); c=np.corrcoef(b.iloc[3:-3],M["xa_act"].iloc[3:-3])[0,1]
    print(f"    shift{k:+d}: {c:+.3f}"+("  <-0" if k==0 else ""))

def ir(a): a=np.asarray(a,float); a=a[np.isfinite(a)]; return a.mean()/a.std()*np.sqrt(12) if a.std()>0 else np.nan
ret_corr=float(np.corrcoef(M.book_act,M.xa_act)[0,1])
inc_ir=ir(M.book_act)
print(f"\n  return-level active-corr(XATTN, incumbent) = {ret_corr:+.3f}   [orthogonality gate |cor|<0.30]")
print(f"  incumbent book active IR (this window) = {inc_ir:+.3f}")
print("  fixed-weight blend dIR (DIAGNOSTIC ONLY — not a sizing proposal):")
blend={}
for w in [0.10,0.15,0.20,0.30]:
    ba=(1-w)*M.book_act+w*M.xa_act
    dIR=ir(ba)-inc_ir; blend[w]=float(dIR)
    print(f"    w_xattn={w:.2f}: blend active IR={ir(ba):+.3f}  dIR={dIR:+.3f}  {'>=0.05 PASS' if dIR>=0.05 else '<0.05'}")

import json
json.dump({"score_rank_corr":score_corr,"return_active_corr_vs_incumbent":ret_corr,
           "incumbent_active_ir_window":inc_ir,"blend_dIR_diagnostic":blend,
           "orthogonality_gate":"|cor|<0.30 AND dIR>=0.05","n_common_months":int(len(M))},
          open(STG+"orthogonality.json","w"),indent=2)
print("\n[SAVED] orthogonality.json")
