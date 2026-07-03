"""run_discovery_battery.py — discovery 완전 배터리 (family × horizon × model{ICw,RMT}) + 방화벽 게이트.
RAW substrate(327 pre-C13). IC-가중(supervised within-family) vs RMT-집계(factor-of-factors) vs EW.
decay: full + recent(2021+). 게이트: placebo(200 perm) · seed(5 subset 안정성) · book-marginal(ΔIR vs score_eff).
발굴전용 — 자본 governor 수동. PIT: 모든 IC/고유벡터 trailing.
"""
import os, sys, numpy as np, pandas as pd, json
os.environ.setdefault("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0,"02_Infrastructure/discovery")
from discovery_explore import ensure_panel, bm_fwd_map, load_families, nw_t, HORIZONS_ALL
R=os.environ["QM_ROOT"]; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
panel=ensure_panel()
excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
fcols=[c for c in panel.columns if c not in excl]
fam,dirn=load_families(fcols); dvec={f:dirn.get(f,1.0) for f in fcols}
months=sorted(panel["ym"].unique()); mi={m:i for i,m in enumerate(months)}; bmf=bm_fwd_map()
ymv=panel["ym"].values; tkv=panel["Ticker"].values
# per-month standardize each factor (횡단 z)
Xraw=panel[fcols].values.astype(float); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z)
Dv=np.array([dvec[f] for f in fcols])
# forward-H per-factor trailing IC (PIT): 월별 횡단 IC → trailing 12m mean shift1
def factor_ic_panel(H):
    FH=panel[f"F{H}"].values.astype(float)
    icm=np.full((len(months),len(fcols)),np.nan)
    for i,t in enumerate(months):
        m=ymv==t; y=FH[m]; ok=np.isfinite(y)
        if ok.sum()<25: continue
        yz=(y[ok]-np.nanmean(y[ok]))/(np.nanstd(y[ok])+1e-9)
        icm[i]=(Z[m][ok].T@yz)/ok.sum()   # 횡단 IC per factor
    df=pd.DataFrame(icm)
    tw=df.rolling(12,min_periods=6).mean().shift(H)   # ★PIT 수리: IC[s]는 s+H에 실현 → lag H (구 shift(1)=horizon-lag 누수)
    return tw.values  # months x factors
IC={H:factor_ic_panel(H) for H in (1,3,6,12)}
def bt(score,H,recent=False,top_n=25):
    rec=[]; prev=set(); dec=[m for m in months[60:] if mi[m]%max(H,1)==0 and (not recent or m>='2021-01')]
    for t in dec:
        te=np.where(ymv==t)[0]; s=score[te]; ok=np.isfinite(s)
        if ok.sum()<top_n: continue
        idx=te[ok][np.argpartition(-s[ok],top_n-1)[:top_n]]; sel=set(tkv[idx])
        g=np.nanmean(panel[f"F{H}"].values[idx]); to=2*(top_n-len(sel&prev))/top_n if prev else 1.0
        rec.append((g-to*0.0015,bmf(t,H))); prev=sel
    r=pd.DataFrame(rec,columns=["net","bm"]).dropna(); a=(r.net-r.bm).values
    if len(a)<6: return {"IR":np.nan,"t":np.nan,"n":len(a)}
    return {"IR":a.mean()/a.std()*np.sqrt(12/H) if a.std()>0 else np.nan,"t":nw_t(a),"n":len(a)}
def score_icw(fidx,H):   # IC-가중 (supervised within-family, dir 포함 via IC 부호)
    tw=IC[H]; W=np.zeros((len(months),len(fidx)))
    sc=np.full(len(panel),np.nan)
    for i,t in enumerate(months):
        w=tw[i,fidx];
        if not np.any(np.isfinite(w)): continue
        w=np.nan_to_num(w); m=ymv==t
        if m.sum(): sc[m]=Z[m][:,fidx]@w
    return sc
def score_rmt(fidx,H,refit=12):  # 비지도 RMT-집계 within-family
    sc=np.full(len(panel),np.nan); V=None; OOS=months[60:]; sub=Z[:,fidx]; L=len(fidx)
    for i,t in enumerate(OOS):
        if i%refit==0:
            tr=np.array([mi[m] for m in ymv])<mi[t]
            if tr.sum()<60 or L<3: V=None; continue
            C=np.corrcoef(sub[tr].T); C=np.nan_to_num(C)
            ev,evec=np.linalg.eigh(C); ev=ev[::-1]; evec=evec[:,::-1]
            lam=(1+np.sqrt(L/tr.sum()))**2; ns=max(int((ev>lam).sum()),1); V=evec[:,:ns]
            SFtr=sub[tr]@V; ytr=panel["F1"].values[tr]; ytr=np.nan_to_num(ytr)
            prem=np.array([np.corrcoef(SFtr[:,j],ytr)[0,1] for j in range(V.shape[1])]); prem=np.nan_to_num(prem)
        m=ymv==t
        if m.sum() and V is not None: sc[m]=(sub[m]@V)@prem
    return sc
def score_ew(fidx,H):
    m=Z[:,fidx]*Dv[fidx]; return np.nanmean(m,axis=1)
FAMS=["earnings_rev","earnings","value","momentum","quality","idiovol","liquidity","growth","accrual","all"]
rows=[]
for fm in FAMS:
    fl=fam.get(fm,[]); fidx=np.array([fcols.index(f) for f in fl if f in fcols])
    if len(fidx)<3: continue
    for H in (1,3,6,12):
        for mdl,fn in [("ICw",score_icw),("RMT",score_rmt),("EW",score_ew)]:
            s=fn(fidx,H); full=bt(s,H); recent=bt(s,H,recent=True)
            rows.append({"family":fm,"H":H,"model":mdl,"nfac":len(fidx),
                         "full_t":full["t"],"full_IR":full["IR"],"recent_t":recent["t"],"recent_IR":recent["IR"],"n":full["n"]})
res=pd.DataFrame(rows)
print("=== discovery 완전 배터리 (family×horizon×model) — recent_t 상위 ===")
top=res[np.isfinite(res.recent_t)].sort_values("recent_t",ascending=False).head(15)
print(top[["family","H","model","nfac","full_t","recent_t","full_IR","recent_IR"]].to_string(index=False))
# ── 방화벽: 최고 후보 placebo + seed + book-marginal ──
cand=res[np.isfinite(res.recent_t)].sort_values("recent_t",ascending=False).iloc[0]
fmc,Hc,mdc=cand.family,int(cand.H),cand.model; fl=fam[fmc]; fidx=np.array([fcols.index(f) for f in fl if f in fcols])
print(f"\n최고 후보: {fmc}@H{Hc}/{mdc} recent_t={cand.recent_t:.2f} full_t={cand.full_t:.2f}")
fn={"ICw":score_icw,"RMT":score_rmt,"EW":score_ew}[mdc]
# placebo: 같은 크기 랜덤 팩터셋
rng=np.random.RandomState(1); pl=[]
for _ in range(200):
    j=rng.choice(len(fcols),len(fidx),replace=False); r=bt(score_icw(j,Hc),Hc,recent=True)
    if np.isfinite(r["t"]): pl.append(r["t"])
pl=np.array(pl); pct=(pl<cand.recent_t).mean()*100
# seed: 팩터 50% 부분집합 5회
seeds=[]
for sd in range(5):
    rs=np.random.RandomState(sd); j=rs.choice(fidx,max(3,len(fidx)//2),replace=False); r=bt(fn(j,Hc),Hc,recent=True); seeds.append(r["t"])
# book-marginal: score_eff + candidate → ΔIR
seff=panel["score_eff"].fillna(0).values; cscore=fn(fidx,Hc); comb=np.nan_to_num(seff)+np.nan_to_num(cscore)
base_ir=bt(seff,Hc)["IR"]; comb_ir=bt(comb,Hc)["IR"]
print(f"\n=== 방화벽 게이트 ===")
print(f"  placebo: recent_t {cand.recent_t:.2f} vs 랜덤200 → {pct:.1f}%ile (>97.5% 통과) pl95={np.percentile(pl,95):.2f}")
print(f"  seed(50% subset x5) recent_t: {[round(x,2) if np.isfinite(x) else None for x in seeds]} (부호안정·소분산이면 견고)")
print(f"  book-marginal: score_eff IR {base_ir:.2f} → +cand {comb_ir:.2f} (ΔIR {comb_ir-base_ir:+.2f}; ≥0.05 통과)")
res.to_csv(OUT+"/discovery_battery_results.csv",index=False)
json.dump({"cand":f"{fmc}@H{Hc}/{mdc}","recent_t":float(cand.recent_t),"placebo_pct":float(pct),"seeds":[float(x) if np.isfinite(x) else None for x in seeds],"dIR":float(comb_ir-base_ir)},open(OUT+"/discovery_battery_gate.json","w"))
print("\nsaved discovery_battery_results.csv + gate.json")
