"""run_discovery_fof.py — 제대로 적용: 플랜의 factor-of-factors(집계 vs supervised)를 *RAW substrate* + horizon 축으로.
FWL 잔차가 아닌 RAW 327팩터(explore_panel, pre-C13)에서 공통구조 추출. discovery 방법론(raw·horizon·placebo).
비교: supervised(raw composite, dir-adjusted) vs 비지도 RMT-집계(raw 팩터 상관→signal 고유벡터→premium가중). horizon 1/3/6/12.
게이트: recent(2021+) PORT_t + placebo(200 랜덤 2팩터). 발굴전용(자본 governor 수동).
"""
import os, sys, numpy as np, pandas as pd
os.environ.setdefault("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0,"02_Infrastructure/discovery")
from discovery_explore import ensure_panel, bm_fwd_map, load_families, nw_t, HORIZONS_ALL
R=os.environ["QM_ROOT"]; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
panel=ensure_panel()
excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
fcols=[c for c in panel.columns if c not in excl]
fam,dirn=load_families(fcols)
dvec=np.array([dirn.get(f,1.0) for f in fcols])
print(f"RAW substrate: {len(fcols)} 팩터 (pre-C13, non-FWL)")
months=sorted(panel["ym"].unique()); mi={m:i for i,m in enumerate(months)}; bmf=bm_fwd_map()
X=panel[fcols].values.copy(); X=np.where(np.isfinite(X),X,0.0)
Xd=X*dvec  # direction-adjusted (higher=better)
ymv=panel["ym"].values; tkv=panel["Ticker"].values
# per-month standardize (횡단 z) for aggregation stability
def cs_z(M,ym):
    out=M.copy()
    for t in np.unique(ym):
        m=ym==t; v=M[m]; mu=v.mean(0); sd=v.std(0); sd[sd<1e-9]=1; out[m]=(v-mu)/sd
    return out
Xz=cs_z(Xd,ymv)
def backtest(score,H,top_n=25):
    rec=[]; prev=set()
    dec=[m for m in months[60:] if mi[m]%max(H,1)==0]
    for t in dec:
        te=np.where(ymv==t)[0]; s=score[te]; ok=np.isfinite(s)
        if ok.sum()<top_n: continue
        idx=te[ok][np.argpartition(-s[ok],top_n-1)[:top_n]]; sel=set(tkv[idx])
        gross=np.nanmean(panel[f"F{H}"].values[idx]); to=2*(top_n-len(sel&prev))/top_n if prev else 1.0
        rec.append((gross-to*0.0015,bmf(t,H))); prev=sel
    r=pd.DataFrame(rec,columns=["net","bm"]).dropna(); a=(r.net-r.bm).values
    if len(a)<8: return None
    return {"IR":a.mean()/a.std()*np.sqrt(12/H) if a.std()>0 else np.nan,"PORT_t":nw_t(a),"n":len(a)}
def seg(score,H):
    full=backtest(score,H);
    # recent 2021+
    rec=[]; prev=set(); dec=[m for m in months[60:] if mi[m]%max(H,1)==0 and m>='2021-01']
    for t in dec:
        te=np.where(ymv==t)[0]; s=score[te]; ok=np.isfinite(s)
        if ok.sum()<25: continue
        idx=te[ok][np.argpartition(-s[ok],24)[:25]]; g=np.nanmean(panel[f"F{H}"].values[idx]); rec.append((g,bmf(t,H)))
    rr=pd.DataFrame(rec,columns=["net","bm"]).dropna(); ar=(rr.net-rr.bm).values
    rt=nw_t(ar) if len(ar)>=8 else np.nan
    return full, rt
# ── supervised: raw composite (dir-adjusted mean) ──
def sup_score(): return Xz.mean(1)
# ── 비지도 RMT-집계: raw 팩터 상관 → signal 고유벡터(λ+ 초과) → premium(trailing IC) 가중 ──
def urmt_score(H,refit=12):
    L=Xz.shape[1]; pred=np.full(len(panel),np.nan); V=None; nsig=None
    OOS=months[60:]
    for i,t in enumerate(OOS):
        if i%refit==0:
            tr=np.array([mi[m] for m in ymv])<mi[t]
            C=np.corrcoef(Xz[tr].T); C=np.nan_to_num(C)
            ev,evec=np.linalg.eigh(C); ev=ev[::-1]; evec=evec[:,::-1]
            Ns=tr.sum(); lam=(1+np.sqrt(L/Ns))**2; nsig=max(int((ev>lam).sum()),1)
            V=evec[:,:nsig]
            # super-factor 노출 (전체) + premium via trailing IC
            SF_all=Xz@V  # N x nsig
        m=ymv==t
        if m.sum() and V is not None:
            # premium: trailing IC of each super-factor (IS)
            SFtr=Xz[tr]@V; ytr=panel["F1"].values[tr]
            prem=np.array([np.corrcoef(SFtr[:,j],np.nan_to_num(ytr))[0,1] for j in range(V.shape[1])])
            prem=np.nan_to_num(prem)
            pred[m]=(Xz[m]@V)@prem
    return pred
print("\n=== RAW substrate: supervised vs 비지도 RMT-집계 (horizon별) ===")
print(f"{'method':16s}{'H':>3s}{'full_IR':>9s}{'full_t':>8s}{'recent_t':>9s}")
res=[]
sup=sup_score()
for H in (1,3,6,12):
    f,rt=seg(sup,H);
    if f: print(f"{'SUP-raw':16s}{H:3d}{f['IR']:9.2f}{f['PORT_t']:8.2f}{rt:9.2f}"); res.append(("SUP",H,f['PORT_t'],rt))
for H in (1,3,6,12):
    us=urmt_score(H); f,rt=seg(us,H)
    if f: print(f"{'U-rmt-raw':16s}{H:3d}{f['IR']:9.2f}{f['PORT_t']:8.2f}{rt:9.2f}"); res.append(("URMT",H,f['PORT_t'],rt))
# placebo: 최고 recent_t 후보 vs 200 랜덤 2팩터
best=max([r for r in res if np.isfinite(r[3])],key=lambda z:z[3]); print(f"\n최고 recent_t: {best[0]}@H{best[1]} t={best[3]:.2f}")
H=best[1]; pl=[]
rng=np.random.RandomState(42)
for _ in range(200):
    j=rng.choice(len(fcols),2,replace=False); sc2=Xz[:,j].mean(1); _,rt=seg(sc2,H)
    if np.isfinite(rt): pl.append(rt)
pl=np.array(pl); pct=(pl<best[3]).mean()*100
print(f"placebo(H{H}): 최고 후보 t={best[3]:.2f} vs 랜덤 200 → pctile={pct:.1f}% (>97.5%=다중검정 통과) pl95={np.percentile(pl,95):.2f}")
pd.DataFrame(res,columns=["method","H","full_t","recent_t"]).to_csv(OUT+"/discovery_fof_results.csv",index=False)
print("saved discovery_fof_results.csv")
