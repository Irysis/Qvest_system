# Phase 1 (Round 3) — RAW 시퀀스 모델 (① 우회: factor-DB 밖, 모델이 자기피처 학습)
#   종목별 trailing-120일 OHLCV/Ret/Vol 시퀀스 → 1D-CNN → forward 1M(횡단면 z) 예측.
#   factor-DB 결합/feature 축(Round1·2) 둘 다 최근死 → raw 미세구조가 최근 알파 갖나 검증.
#   판정: 21-26 순 active IR. 시간 무제한(백그라운드).
import numpy as np, pandas as pd, os, warnings
warnings.filterwarnings("ignore")
import torch, torch.nn as nn
torch.manual_seed(42); np.random.seed(42)
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/phase1_raw_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")

W=120; CH=6
# universe + target from panel
pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")[["ym","Ticker","fwd_ret_1m"]].dropna()
pan["y"]=pan.groupby("ym")["fwd_ret_1m"].transform(lambda s:(s-s.mean())/(s.std()+1e-9))
months=sorted(pan["ym"].unique()); OOS=months[60:]; midx={m:i for i,m in enumerate(months)}

CACHESEQ=OUT+f"/phase1_seq_W{W}.npz"
if os.path.exists(CACHESEQ):
    log("seq cache 로드"); z=np.load(CACHESEQ,allow_pickle=True)
    X=z["X"]; keys=pd.DataFrame(z["keys"],columns=["ym","Ticker"])
else:
    log("RAW 시퀀스 조립 중 (RAWDATA)...")
    import pyarrow.parquet as pq
    rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Open","High","Low","Close","Vol","Ret"]).to_pandas()
    rd["Date"]=pd.to_datetime(rd["Date"]); rd=rd.sort_values(["Ticker","Date"]).reset_index(drop=True)
    rd["ym"]=rd["Date"].dt.strftime("%Y-%m")
    rd["prevC"]=rd.groupby("Ticker")["Close"].shift(1)
    rd["c_ret"]=rd["Ret"].clip(-0.5,0.5)
    rd["c_rng"]=((rd["High"]-rd["Low"])/rd["Close"]).clip(0,0.5)
    rd["c_body"]=((rd["Close"]-rd["Open"])/rd["Open"]).clip(-0.5,0.5)
    rd["c_gap"]=((rd["Open"]/rd["prevC"]-1)).clip(-0.5,0.5)
    rd["c_lvol"]=np.log1p(rd["Vol"].clip(lower=0))
    rd["c_dprice"]=np.log(rd["Close"].clip(lower=1e-6))
    feat=["c_ret","c_rng","c_body","c_gap","c_lvol","c_dprice"]
    need=set(map(tuple, pan[["ym","Ticker"]].values))
    Xs=[]; ks=[]
    for tk,g in rd.groupby("Ticker",sort=False):
        g=g.reset_index(drop=True)
        last_idx=g.groupby("ym").tail(1)  # 월말 행
        arr=g[feat].values
        for _,r in last_idx.iterrows():
            ym=r["ym"]
            if (ym,tk) not in need: continue
            i=r.name  # row index in g
            if i+1<W: continue
            seq=arr[i-W+1:i+1].copy()  # (W,CH)
            # per-seq 정규화(레벨 제거): lvol·dprice는 z, 나머지는 그대로(이미 비율)
            for c in (4,5): seq[:,c]=(seq[:,c]-seq[:,c].mean())/(seq[:,c].std()+1e-9)
            Xs.append(seq.astype(np.float32)); ks.append((ym,tk))
    X=np.stack(Xs); keys=pd.DataFrame(ks,columns=["ym","Ticker"])
    np.savez_compressed(CACHESEQ, X=X, keys=keys.values)
    log(f"조립 완료: X {X.shape}")

# merge target
keys=keys.merge(pan[["ym","Ticker","y","fwd_ret_1m"]],on=["ym","Ticker"],how="left")
ok=keys["y"].notna().values; X=X[ok]; keys=keys[ok].reset_index(drop=True)
ymv=keys["ym"].values; yv=keys["y"].values.astype(np.float32)
log(f"샘플 {X.shape} | OOS {OOS[0]}~{OOS[-1]}")

class CNN(nn.Module):
    def __init__(s,ch=CH):
        super().__init__()
        s.net=nn.Sequential(nn.Conv1d(ch,16,5,padding=2),nn.ReLU(),nn.Conv1d(16,16,5,padding=2),nn.ReLU(),
                            nn.AdaptiveAvgPool1d(1),nn.Flatten(),nn.Linear(16,16),nn.ReLU(),nn.Dropout(0.3),nn.Linear(16,1))
    def forward(s,x): return s.net(x).squeeze(-1)

def train_predict(trX,trY,teX,epochs=8):
    m=CNN(); opt=torch.optim.Adam(m.parameters(),lr=1e-3,weight_decay=1e-4); lossf=nn.MSELoss()
    trX_t=torch.tensor(trX.transpose(0,2,1)); trY_t=torch.tensor(trY)
    n=len(trX_t); bs=2048
    for ep in range(epochs):
        perm=torch.randperm(n)
        for i in range(0,n,bs):
            idx=perm[i:i+bs]; opt.zero_grad()
            out=m(trX_t[idx]); loss=lossf(out,trY_t[idx]); loss.backward(); opt.step()
    m.eval()
    with torch.no_grad(): p=m(torch.tensor(teX.transpose(0,2,1))).numpy()
    return p

def net_series(sig):
    d=pd.DataFrame({"ym":ymv,"tk":keys["Ticker"].values,"fwd":keys["fwd_ret_1m"].values,"sig":sig})
    d=d[d["ym"].isin(set(OOS))].dropna(subset=["sig","fwd"])
    bm=pd.read_parquet(CACHE+"/benchmark.parquet"); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
    bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
    bmm=bm.groupby("ym")[bc].apply(lambda r:np.expm1(np.log1p(r).sum())).sort_index().shift(-1)
    recs=[]; prev=set()
    for ym,g in d.groupby("ym",sort=True):
        sv=g["sig"].values; idx=np.argpartition(-sv,min(25,len(sv)-1))[:25]
        sel=set(g["tk"].values[idx]); gross=g["fwd"].values[idx].mean()
        to=2*(25-len(sel&prev))/25 if prev else 1.0
        recs.append((ym,gross-to*0.0015,bmm.get(ym,np.nan))); prev=sel
    return pd.DataFrame(recs,columns=["ym","net","bm"])
def ir(s,lo=None,hi=None):
    r=s if lo is None else s[(s["ym"]>=lo)&(s["ym"]<=hi)]
    r=r.dropna()
    if len(r)<7: return np.nan
    a=r["net"].values-r["bm"].values; return a.mean()/a.std()*np.sqrt(12)

# walk-forward: retrain 12m, 즉시 다음 12개월 일괄 예측
order=np.array([midx[y] for y in ymv])
sig=np.full(len(X),np.nan)
i=0
while i<len(OOS):
    ym=OOS[i]; trm=order<midx[ym]
    if trm.sum()<5000: i+=1; continue
    block=OOS[i:i+12]; tem=np.isin(ymv,block)
    if tem.sum()>0:
        p=train_predict(X[trm],yv[trm],X[tem])
        sig[tem]=p
    log(f"  trained@{ym} → predicted {block[0]}..{block[-1]} (te n={tem.sum()})")
    i+=12

s=net_series(sig)
v=[ir(s),ir(s,"2010-01","2015-12"),ir(s,"2016-01","2020-12"),ir(s,"2021-01","2026-12")]
log(f"\n{'RAW-CNN seq':30s} {'full':>7} {'10-15':>7} {'16-20':>7} {'21-26':>7}")
log(f"{'RAW-CNN seq':30s} {v[0]:7.3f} {v[1]:7.3f} {v[2]:7.3f} {v[3]:7.3f}{' <-21-26+' if v[3]>0.3 else ''}")
log("=== done ===")
