"""xattn_score.py MODE — Cross-Sectional Attention 슈퍼팩터 (신규 아키텍처).
기존 5방법(KNS/IPCA/BMA/E2E/SPO+)은 全부 종목별 독립사상(점수=자기특성만). 본 모델은 **횡단면을 함께**:
매월 N종목이 self-attention(inducing-point/set-attention)으로 서로 참조 → 상대위치·peer·crowding 학습.
- embed: Linear(327→d) → hᵢ
- 횡단 context: k 학습쿼리로 월별 attention-pool(종목에 대해 softmax) → context[t] (k×d), 각 종목에 broadcast
- rep = [hᵢ, context_flat, hᵢ−context_mean(상대편차)] → head → score, gate
- 목적: E2E 검증된 net active Sharpe 직접손실 + hard-concrete L0 gate (마이크로캡 제거). PIT rolling 96월.
배포점수 s=gate·score → canonical top-25 EW 계약. 세션 재시작: 새 아키텍처가 KR 벽(post-2017 감쇠·마이크로캡) 넘나 검증.
"""
import os, sys, numpy as np, pandas as pd, torch, torch.nn as nn
SEED=int(sys.argv[2]) if len(sys.argv)>2 else 0
torch.manual_seed(SEED); np.random.seed(SEED)
SUF=f"_s{SEED}" if SEED!=0 else ""
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
midx_all=np.array([mi[t] for t in ymv],dtype=np.int64)
Lg(f"[XATTN {MODE}] rows {len(panel)} T={T} median N {int(panel.groupby('ym').size().median())} H={H} (torch {torch.__version__})")

D=24; K=4; BETA=3.0; G0,ZE,TEMP=-0.1,1.1,0.5
class XAttn(nn.Module):
    def __init__(s,H,d=D,k=K):
        super().__init__()
        s.emb=nn.Sequential(nn.Linear(H,d),nn.LayerNorm(d),nn.ReLU(),nn.Linear(d,d),nn.LayerNorm(d))
        s.Q=nn.Parameter(torch.randn(k,d)*0.1)   # 학습 inducing 쿼리 (횡단면 요약)
        s.k=k; s.d=d
        s.head=nn.Sequential(nn.Linear(d*(k+2),d),nn.ReLU(),nn.Linear(d,2))
    def forward(s,x,midx,nT):
        h=s.emb(x)                                  # (M,d)
        al=(h@s.Q.T).clamp(-15,15)                  # (M,k) 종목-쿼리 affinity
        e=torch.exp(al)
        denom=torch.zeros(nT,s.k).index_add_(0,midx,e)+1e-8   # (nT,k) 월별 정규화
        a=e/denom[midx]                              # (M,k) 월내 종목 attention
        contrib=a.unsqueeze(-1)*h.unsqueeze(1)       # (M,k,d)
        ctx=torch.zeros(nT,s.k,s.d).index_add_(0,midx,contrib)  # (nT,k,d) 횡단 context
        ci=ctx[midx]                                 # (M,k,d)
        rep=torch.cat([h, ci.reshape(len(h),-1), h-ci.mean(1)],dim=1)  # [자기, context, 상대편차]
        o=s.head(rep); return o[:,0], o[:,1]
def hc_gate(logit, train=True):
    if train:
        u=torch.rand_like(logit).clamp(1e-6,1-1e-6); sg=torch.sigmoid((torch.log(u)-torch.log(1-u)+logit)/TEMP)
    else: sg=torch.sigmoid(logit)
    return (sg*(ZE-G0)+G0).clamp(0,1)
def l0_prob(logit): return torch.sigmoid(logit - TEMP*np.log(-G0/ZE))
def seg_port(score,gate,r,midx,nT):
    e=gate*torch.exp((BETA*score).clamp(-20,20)); denom=torch.zeros(nT).index_add_(0,midx,e)+1e-8
    w=e/denom[midx]; port=torch.zeros(nT).index_add_(0,midx,w*r); return port

def train_window(idx_rows, midx_local, r_local, bench_local, nTw, epochs=250):
    net=XAttn(H); opt=torch.optim.Adam(net.parameters(),lr=3e-3,weight_decay=1e-5)
    Zt=torch.from_numpy(Z[idx_rows]); rt=torch.from_numpy(r_local.astype(np.float32)); mt=torch.from_numpy(midx_local)
    bt=torch.from_numpy(bench_local.astype(np.float32)); am=np.unique(midx_local)
    for ep in range(epochs):
        opt.zero_grad(); sc,ga=net(Zt,mt,nTw); gate=hc_gate(ga,True)
        port=seg_port(sc,gate,rt,mt,nTw); act=(port-bt)[am]
        sharpe=act.mean()/(act.std()+1e-6)*np.sqrt(12); l0=l0_prob(ga).mean()
        (-sharpe+0.5*l0).backward(); opt.step()
    return net

min_hist=60; refit=12; WIN=96
def ym2date(ym): return pd.Timestamp(ym+"-01")+pd.offsets.MonthEnd(0)
rows=[]; net=None
import time as _t
for m in range(min_hist,T):
    mm=months[m]
    if (m-min_hist)%refit==0 or net is None:
        lo=max(0,m-WIN); trmask=(midx_all>=lo)&(midx_all<m)&np.isfinite(F1); idx_rows=np.where(trmask)[0]
        loc=(midx_all[idx_rows]-lo).astype(np.int64); nTw=int(loc.max())+1
        r_local=F1[idx_rows]; b_local=np.array([bmap.get(months[lo+j],np.nan) for j in range(nTw)],float)
        b_local=np.nan_to_num(b_local,nan=np.nanmean(b_local)); t0=_t.time()
        net=train_window(idx_rows,loc,r_local,b_local,nTw); Lg(f"  [XATTN {MODE}] refit {mm} rows {len(idx_rows)} ({_t.time()-t0:.0f}s)")
    ms=np.where(ymv==mm)[0]
    with torch.no_grad():
        sc,ga=net(torch.from_numpy(Z[ms]),torch.zeros(len(ms),dtype=torch.int64),1); gate=hc_gate(ga,False)
        s=(gate*(sc-sc.mean())).numpy()
    for tk,a in zip(tkv[ms],s): rows.append((ym2date(mm),tk,float(a)))
d=pd.DataFrame(rows,columns=["Date","Ticker","score"]); d.to_parquet(OUT+f"/scores_XATTN_{MODE}{SUF}.parquet",index=False)
d2=d.copy(); d2["ym"]=pd.to_datetime(d2.Date).dt.to_period("M").astype(str); ics=[]
for ym,g in d2.groupby("ym"):
    ms=ymv==ym; y=pd.Series(F1[ms],index=tkv[ms]); c=pd.concat([g.set_index("Ticker")["score"],y],axis=1).dropna()
    if len(c)>25 and c.iloc[:,0].std()>1e-9: ics.append(np.corrcoef(c.iloc[:,0],c.iloc[:,1])[0,1])
ics=np.array(ics); Lg(f"[XATTN {MODE}] PIT IC mean={ics.mean():+.4f} ICIR={ics.mean()/ics.std()*np.sqrt(12):+.2f} n={len(ics)} 결정월 {d.Date.nunique()} → scores_XATTN_{MODE}.parquet")
