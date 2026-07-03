"""spo_score.py MODE — Elmachtoub-Grigas (2022) "Smart Predict, then Optimize" (SPO+) decision-focused 학습.
예측정확도(IC) 아닌 **decision regret**(top-25 long-only EW 선택품질)을 직접 최소화 — "rank-IC≠PORT_t"(measurement §2) 학습단계 해소.
결정 oracle: w*(a) = top-25 EW by a (argmax a'w s.t. long-only EW top-25).
SPO+ subgradient(ĉ): 2(w*(2ĉ−c) − w*(c)). 선형 예측 ĉ=Zθ (E-G: 선형+SPO+가 RF 지배). PIT 확장윈도우 연간 refit.
배포점수 s=Zθ̂ → canonical top-25 EW 계약(apples-to-apples). c=실현 초과수익(F1−bench).
"""
import os, sys, numpy as np, pandas as pd
def Lg(*a): print(*a,flush=True)
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; os.environ.setdefault("QM_ROOT",R)
sys.path.insert(0,R+"/02_Infrastructure/discovery")
from discovery_explore import ensure_panel, HORIZONS_ALL
OUT=R+"/04_Research/factor_rotation/fof_first_slice"
MODE=sys.argv[1] if len(sys.argv)>1 else "canonical"
_p=ensure_panel(); excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
FCOLS=[c for c in _p.columns if c not in excl]; H=len(FCOLS)
M=pd.read_parquet(OUT+"/kns_master_panel.parquet")
if MODE=="canonical": mask=(M.K200f|M.KQ150f)
elif MODE=="allclean": mask=(M.nret>=15)&(~M.bad)
elif MODE=="allliq": mask=(M.nret>=15)&(~M.bad)&(M.adv>=2e8)
else: raise SystemExit("MODE?")
panel=M[mask].copy(); months=sorted(panel.ym.unique()); T=len(months); mi={m:i for i,m in enumerate(months)}
ymv=panel.ym.values; tkv=panel.Ticker.values; F1=panel.F1.values.astype(float)
bench=pd.read_parquet(OUT+"/kns_master_bench.parquet"); bench["ym"]=pd.to_datetime(bench.Date).dt.to_period("M").astype(str)
bmap=dict(zip(bench.ym,bench.BM_Ret))
Xraw=panel[FCOLS].values.astype(float); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1.0; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z)
# 월별 (Z_t, c_t=excess) 사전조직
by_m={}
for k,t in enumerate(months):
    m=ymv==t; r=F1[m]; ok=np.isfinite(r)
    if ok.sum()<26: continue
    c=r[ok]-bmap.get(t,0.0)   # 초과수익
    by_m[k]=(Z[m][ok], c, np.where(m)[0][ok])
Lg(f"[SPO {MODE}] rows {len(panel)} T={T} valid월 {len(by_m)} H={H}")

def topN_ew(a, N=25):  # oracle: argmax a'w, w=top-N EW
    w=np.zeros(len(a)); idx=np.argpartition(-a, min(N,len(a)-1))[:N]; w[idx]=1.0/len(idx); return w

def train_spo(win_ks, epochs=250, lr=0.2, l2=1e-3):
    th=np.zeros(H)
    # 사전: top-N by c (실현-최적, 불변)
    wc={k:topN_ew(by_m[k][1]) for k in win_ks}
    for ep in range(epochs):
        g=np.zeros(H)
        for k in win_ks:
            Zt,c,_=by_m[k]; chat=Zt@th
            wh=topN_ew(2*chat - c)            # w*(2ĉ−c)
            g += Zt.T@(wh - wc[k])            # SPO+ subgradient (Z' (w*(2ĉ−c) − w*(c)))
        g=g/len(win_ks) + l2*th
        th -= lr*g
    return th

min_hist=60; refit=12; WIN=72  # 확장(사실상 전체 과거)
def ym2date(ym): return pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0)
rows=[]; th=None
for m in range(min_hist,T):
    mm=months[m]
    if (m-min_hist)%refit==0 or th is None:
        win_ks=[k for k in by_m if (m-WIN)<=k<m]      # [m-WIN, m) 실현 (PIT)
        if len(win_ks)<min_hist: continue
        th=train_spo(win_ks)
    ms=np.where(ymv==mm)[0]; s=Z[ms]@th
    for tk,a in zip(tkv[ms],s): rows.append((ym2date(mm),tk,float(a)))
d=pd.DataFrame(rows,columns=["Date","Ticker","score"]); d.to_parquet(OUT+f"/scores_SPO_{MODE}.parquet",index=False)
d2=d.copy(); d2["ym"]=pd.to_datetime(d2.Date).dt.to_period("M").astype(str); ics=[]
for ym,g in d2.groupby("ym"):
    ms=ymv==ym; y=pd.Series(F1[ms],index=tkv[ms]); c=pd.concat([g.set_index("Ticker")["score"],y],axis=1).dropna()
    if len(c)>25 and c.iloc[:,0].std()>1e-9: ics.append(np.corrcoef(c.iloc[:,0],c.iloc[:,1])[0,1])
ics=np.array(ics); Lg(f"[SPO {MODE}] PIT IC mean={ics.mean():+.4f} ICIR={ics.mean()/ics.std()*np.sqrt(12):+.2f} n={len(ics)} 결정월 {d.Date.nunique()} → scores_SPO_{MODE}.parquet")
