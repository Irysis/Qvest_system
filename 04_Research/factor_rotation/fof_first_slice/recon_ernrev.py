"""recon_ernrev.py — 스캔 recent_t 4.35 vs deployable sleeve IR 0.34 갭 규명.
earnings_rev를 3방식으로 측정: (A)스캔식 분기 non-overlap H=3, (B)월간 overlap 3M, (C)월간 hold-1M(H=1).
+ top-25 name persistence(turnover 진단). 갭이 overlap/sampling이면 real, 아니면 construction 차이."""
import sys, os
os.environ.setdefault("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0,"02_Infrastructure/discovery")
from discovery_explore import ensure_panel, bm_fwd_map, load_families, nw_t, HORIZONS_ALL
import pandas as pd, numpy as np
panel=ensure_panel()
excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
fcols=[c for c in panel.columns if c not in excl]; fam,dirn=load_families(fcols)
er=fam["earnings_rev"]; panel["sig"]=panel[er].fillna(0.0).values@np.array([dirn.get(f,1.0) for f in er])
bmf=bm_fwd_map(); months=sorted(panel["ym"].unique()); mi={m:i for i,m in enumerate(months)}
hold={}
for t,d in panel.groupby("ym"):
    s=d["sig"].values; tk=d["Ticker"].values; ok=~np.isnan(s)
    if ok.sum()>=25: hold[t]=list(tk[ok][np.argpartition(-s[ok],24)[:25]])
FH={H:{t:dict(zip(d["Ticker"],d[f"F{H}"])) for t,d in panel.groupby("ym")} for H in (1,3)}
def ir(a,H=1): a=a[~np.isnan(a)]; return a.mean()/a.std()*np.sqrt(12/H) if a.std()>0 else np.nan
def seg(df,lo=None,H=1):
    x=df if lo is None else df[df.ym>=lo]; a=(x.net-x.bm).values
    return f"PORT_t={nw_t(a):+.2f} IR={ir(a,H):+.2f} n={len(x)}"

# (A) 스캔식: 분기 non-overlap, H=3
recA=[]
dec=[m for m in months[60:] if mi[m]%3==0]
for t in dec:
    h=hold.get(t);
    if not h: continue
    g=np.nanmean([FH[3][t].get(k,np.nan) for k in h]); recA.append((t,g,bmf(t,3)))
A=pd.DataFrame(recA,columns=["ym","net","bm"]).dropna()   # cost 무시(스캔 근사)

# (B) 월간 overlap 3M
recB=[]; prev=set()
for t in months[60:]:
    forms=[months[mi[t]-k] for k in range(3) if mi[t]-k>=0 and months[mi[t]-k] in hold]
    if not forms: continue
    names={}; [names.__setitem__(k,names.get(k,0)+1) for f in forms for k in hold[f]]
    tot=sum(names.values()); g=sum(FH[1][t].get(k,np.nan)*(v/tot) for k,v in names.items() if not np.isnan(FH[1][t].get(k,np.nan)))
    cur=set(names); to=len(cur^prev)/max(len(cur),1); recB.append((t,g,bmf(t,1))); prev=cur
B=pd.DataFrame(recB,columns=["ym","net","bm"]).dropna()

# (C) 월간 hold-1M (H=1, fresh only)
recC=[]
for t in months[60:]:
    h=hold.get(t)
    if not h: continue
    g=np.nanmean([FH[1][t].get(k,np.nan) for k in h]); recC.append((t,g,bmf(t,1)))
C=pd.DataFrame(recC,columns=["ym","net","bm"]).dropna()

print("=== earnings_rev 측정방식 3종 (cost 무시, 스캔 근사) ===")
print(f" (A) 분기 non-overlap H=3 (스캔식): full {seg(A,None,3)} | recent {seg(A,'2021-01',3)}")
print(f" (B) 월간 overlap 3M       : full {seg(B,None,1)} | recent {seg(B,'2021-01',1)}")
print(f" (C) 월간 hold-1M (fresh)  : full {seg(C,None,1)} | recent {seg(C,'2021-01',1)}")
# name persistence
jac=[]; ks=sorted(hold)
for i in range(1,len(ks)):
    a,b=set(hold[ks[i-1]]),set(hold[ks[i]]); jac.append(len(a&b)/len(a|b))
print(f"\n top-25 월간 Jaccard 중앙={np.median(jac):.2f} (1=완전정적) → earnings 분기 forward-fill로 near-static 여부")
print(f" 유니크 종목 총수(전기간 top-25 합집합)={len(set(sum([hold[k] for k in hold],[])))}")
