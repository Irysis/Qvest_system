"""endtoend_gate.py MODE — Uysal-Li-Mulvey (2021) End-to-End + stochastic-gate 자산선택 충실 구현.
DPL 계보이나 구조 차별점(도훈 confirm): ① hard-concrete L0 stochastic gate로 저품질·저변동 종목 제거(우리 마이크로캡 오염 직격)
② net active Sharpe 직접 손실(예측정확도 아님) ③ turnover 비용 native.
파이프: MLP(327→h→score, gate_logit) → gate=hard_concrete(gate_logit) → w=gate·softmax(score·β) (월별 segment) → active Sharpe.
PIT 확장윈도우(연간 refit, ≤m 실현수익 학습). 배포점수 s=gate_prob·score → canonical top-25 EW 계약(apples-to-apples).
"""
import os, sys, numpy as np, pandas as pd, torch, torch.nn as nn
torch.manual_seed(0); np.random.seed(0)
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
Xraw=panel[FCOLS].values.astype(np.float32); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1.0; Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z).astype(np.float32)
# 월 인덱스 (전역)
midx_all=np.array([mi[t] for t in ymv],dtype=np.int64)
Lg(f"[E2E {MODE}] rows {len(panel)} T={T} median N {int(panel.groupby('ym').size().median())} H={H} (torch {torch.__version__})")

BETA=3.0; G0,ZE=-0.1,1.1; TEMP=0.5  # hard-concrete 파라미터
class Net(nn.Module):
    def __init__(s,H,h=48):
        super().__init__()
        s.body=nn.Sequential(nn.Linear(H,h),nn.ReLU(),nn.Linear(h,h),nn.ReLU())
        s.sc=nn.Linear(h,1); s.ga=nn.Linear(h,1)
    def forward(s,x):
        b=s.body(x); return s.sc(b).squeeze(-1), s.ga(b).squeeze(-1)
def hc_gate(logit, train=True):
    if train:
        u=torch.rand_like(logit).clamp(1e-6,1-1e-6)
        sg=torch.sigmoid((torch.log(u)-torch.log(1-u)+logit)/TEMP)
    else:
        sg=torch.sigmoid(logit)
    return (sg*(ZE-G0)+G0).clamp(0,1)
def l0_prob(logit):  # 기대 gate-open 확률 (L0 penalty)
    return torch.sigmoid(logit - TEMP*np.log(-G0/ZE))

def seg_softmax_port(score, gate, r, midx, nT):
    e=gate*torch.exp((BETA*score).clamp(-20,20))
    denom=torch.zeros(nT).index_add_(0, midx, e)+1e-8
    w=e/denom[midx]
    port=torch.zeros(nT).index_add_(0, midx, w*r)
    to=torch.zeros(nT).index_add_(0, midx, w)  # =1 per active month
    return port, w

def train_window(idx_rows, midx_local, r_local, bench_local, nTw, epochs=300):
    net=Net(H); opt=torch.optim.Adam(net.parameters(),lr=3e-3,weight_decay=1e-5)
    Zt=torch.from_numpy(Z[idx_rows]); rt=torch.from_numpy(r_local.astype(np.float32)); mt=torch.from_numpy(midx_local)
    bt=torch.from_numpy(bench_local.astype(np.float32))
    active_months=np.unique(midx_local)
    for ep in range(epochs):
        opt.zero_grad(); sc,ga=net(Zt); gate=hc_gate(ga,True)
        port,_=seg_softmax_port(sc,gate,rt,mt,nTw)
        act=(port-bt)[active_months]
        sharpe=act.mean()/(act.std()+1e-6)*np.sqrt(12)
        l0=l0_prob(ga).mean()
        loss=-sharpe + 0.5*l0   # L0로 gate 활성 sparsity(저품질 제거) 유도
        loss.backward(); opt.step()
    return net

min_hist=60; refit=12; WIN=96  # rolling 학습창(최근 WIN월) — 학습크기 캡
def ym2date(ym): return pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0)
rows=[]; net=None
for m in range(min_hist,T):
    mm=months[m]
    if (m-min_hist)%refit==0 or net is None:
        lo=max(0,m-WIN)
        trmask=(midx_all>=lo) & (midx_all<m) & np.isfinite(F1)  # [lo,m) 신호월, forward 실현 (PIT)
        idx_rows=np.where(trmask)[0]
        loc_month=(midx_all[idx_rows]-lo).astype(np.int64)  # 0..(m-lo-1)
        nTw=int(loc_month.max())+1
        r_local=F1[idx_rows]; b_local=np.array([bmap.get(months[lo+j],np.nan) for j in range(nTw)],dtype=float)
        b_local=np.nan_to_num(b_local, nan=np.nanmean(b_local))
        import time as _t; t0=_t.time()
        net=train_window(idx_rows, loc_month, r_local, b_local, nTw)
        Lg(f"  [E2E {MODE}] refit {mm} rows {len(idx_rows)} ({_t.time()-t0:.0f}s)")
    ms=np.where(ymv==mm)[0]
    with torch.no_grad():
        sc,ga=net(torch.from_numpy(Z[ms])); gate=hc_gate(ga,False)
        s=(gate*(sc-sc.mean())).numpy()  # 배포점수 = gate_prob·score(중심화)
    for tk,a in zip(tkv[ms],s): rows.append((ym2date(mm),tk,float(a)))
d=pd.DataFrame(rows,columns=["Date","Ticker","score"]); d.to_parquet(OUT+f"/scores_E2E_{MODE}.parquet",index=False)
d2=d.copy(); d2["ym"]=pd.to_datetime(d2.Date).dt.to_period("M").astype(str); ics=[]
for ym,g in d2.groupby("ym"):
    ms=ymv==ym; y=pd.Series(F1[ms],index=tkv[ms]); c=pd.concat([g.set_index("Ticker")["score"],y],axis=1).dropna()
    if len(c)>25 and c.iloc[:,0].std()>1e-9: ics.append(np.corrcoef(c.iloc[:,0],c.iloc[:,1])[0,1])
ics=np.array(ics); Lg(f"[E2E {MODE}] PIT IC mean={ics.mean():+.4f} ICIR={ics.mean()/ics.std()*np.sqrt(12):+.2f} n={len(ics)} 결정월 {d.Date.nunique()} → scores_E2E_{MODE}.parquet")
