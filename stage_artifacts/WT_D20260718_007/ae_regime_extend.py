#!/usr/bin/env python
# ae_regime_extend.py — WT-D20260718_007 R3: AE 신호를 decision 2026-06-01·2026-07-01로 1~2개월 연장
# ae_regime_walkforward.py 동일 구성(동일 SEED·모델·tau) — dec 목록에 두 날짜만 추가 + 별도 OUT.
# 목적: holding 2026-07(=decision 2026-06-01)·2026-08(=decision 2026-07-01)의 AE fire_seq 판정.
# PIT: last_feat_date < decision_date 자동 강제(원본 로직). 패널 2026-07-16까지 → 두 결정 모두 채점 가능.
import os, sys, json
os.environ.setdefault("OMP_NUM_THREADS","1"); os.environ.setdefault("MKL_NUM_THREADS","1")
import numpy as np, pandas as pd
import pyarrow.parquet as pq
import torch, torch.nn as nn
torch.set_num_threads(1)
try: sys.stdout.reconfigure(line_buffering=True)
except Exception: pass
SEED=20260718
np.random.seed(SEED); torch.manual_seed(SEED)

ROOT=os.environ.get("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
os.chdir(ROOT)
PIN=".cache/pins/WT-D20260718_007_r1"
FRED=os.path.join(PIN,"fred_macro_wide.parquet")
BENCH=os.path.join(PIN,"benchmark.parquet")
CARRIER=os.path.join(PIN,"carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")
OUT="stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"   # ★별도 출력 (원본 미덮어씀)
EXTRA_DECISIONS=["2026-06-01","2026-07-01"]                            # ★연장 결정일

L=60; FWD=21; SMOOTH=21
STRIDE=3
D_HID=16; D_LAT=8; DROPOUT=0.1
EPOCHS=25; LR=1e-3; WD=1e-4; PATIENCE=4; BATCH=256
OOS_START_YEAR=2008
M4_FIRE_RATE=0.126
FRED_FEATS=["VIX","Term_Spread","KRW_USD","US_10Y_Yield","US_2Y_Yield","StL_Fin_Stress","Chi_Fin_Cond"]

def build_panel():
    fr=pq.read_table(FRED).to_pandas(); fr["Date"]=pd.to_datetime(fr["Date"]); fr=fr.sort_values("Date")
    bm=pq.read_table(BENCH).to_pandas(); bm["Date"]=pd.to_datetime(bm["Date"]); bm=bm.sort_values("Date").reset_index(drop=True)
    c=bm["BM_Close"].astype(float).values
    bm["kret"]=bm["BM_Ret"].astype(float)
    bm["klog"]=np.log(c/np.roll(c,1)); bm.loc[0,"klog"]=np.nan
    bm["kvol20"]=bm["kret"].rolling(20,min_periods=10).std()
    bm["kcum20"]=c/np.concatenate([np.full(20,np.nan),c[:-20]])-1.0
    bm["kcum60"]=c/np.concatenate([np.full(60,np.nan),c[:-60]])-1.0
    spine=bm[["Date","kret","klog","kvol20","kcum20","kcum60"]].copy()
    m=pd.merge_asof(spine, fr[["Date"]+FRED_FEATS], on="Date", direction="backward")
    feat_cols=["klog","kvol20","kcum20","kcum60"]+FRED_FEATS
    m[feat_cols]=m[feat_cols].ffill()
    m=m.dropna(subset=feat_cols).reset_index(drop=True)
    return m, feat_cols

class SeqAE(nn.Module):
    def __init__(self, nfeat):
        super().__init__()
        self.enc=nn.LSTM(nfeat, D_HID, batch_first=True)
        self.to_lat=nn.Linear(D_HID, D_LAT)
        self.from_lat=nn.Linear(D_LAT, D_HID)
        self.dec=nn.LSTM(D_HID, D_HID, batch_first=True)
        self.out=nn.Linear(D_HID, nfeat)
        self.drop=nn.Dropout(DROPOUT)
    def forward(self,x):
        _,(h,_)=self.enc(x)
        z=self.to_lat(self.drop(h[-1]))
        rep=self.from_lat(z).unsqueeze(1).repeat(1,x.size(1),1)
        d,_=self.dec(rep)
        return self.out(d)

class PointAE(nn.Module):
    def __init__(self, nfeat):
        super().__init__()
        self.net=nn.Sequential(nn.Linear(nfeat,8),nn.GELU(),nn.Linear(8,4),nn.GELU(),
                               nn.Linear(4,8),nn.GELU(),nn.Linear(8,nfeat))
    def forward(self,x): return self.net(x)

def make_seq_windows(end_idx_list, X):
    xs=[i for i in end_idx_list if i-L+1>=0]
    if not xs: return None,None
    return np.stack([X[i-L+1:i+1] for i in xs]).astype(np.float32), np.array(xs)

def train_ae(model, Xtr, Xva, is_seq):
    torch.manual_seed(SEED); np.random.seed(SEED)
    lossf=nn.MSELoss()
    opt=torch.optim.Adam(model.parameters(),lr=LR,weight_decay=WD)
    Xtr_t=torch.tensor(Xtr); Xva_t=torch.tensor(Xva)
    best=1e18; best_state=None; wait=0; n=len(Xtr_t)
    for ep in range(EPOCHS):
        model.train(); perm=torch.randperm(n)
        for b in range(0,n,BATCH):
            bi=perm[b:b+BATCH]; opt.zero_grad()
            xb=Xtr_t[bi]; loss=lossf(model(xb),xb); loss.backward(); opt.step()
        model.eval()
        with torch.no_grad(): vl=lossf(model(Xva_t),Xva_t).item()
        if vl<best-1e-6: best=vl; best_state={k:v.clone() for k,v in model.state_dict().items()}; wait=0
        else: wait+=1
        if wait>=PATIENCE: break
    if best_state is not None: model.load_state_dict(best_state)
    model.eval(); return model

def recon_err_seq(model, W):
    with torch.no_grad():
        r=model(torch.tensor(W.astype(np.float32)))
        e=((r-torch.tensor(W.astype(np.float32)))**2).mean(dim=(1,2)).numpy()
    return e

def recon_err_point(model, V):
    with torch.no_grad():
        r=model(torch.tensor(V.astype(np.float32)))
        e=((r-torch.tensor(V.astype(np.float32)))**2).mean(dim=1).numpy()
    return e

def main():
    panel,feat_cols=build_panel(); nfeat=len(feat_cols)
    Xraw=panel[feat_cols].values.astype(np.float64)
    panel_dates=pd.to_datetime(panel["Date"]).values
    print(f"[panel] rows={len(panel)} feats={nfeat} range {str(panel['Date'].min())[:10]}..{str(panel['Date'].max())[:10]}")
    car=pq.read_table(CARRIER).to_pandas()
    dec=pd.to_datetime(car["decision_date"]).drop_duplicates().sort_values().reset_index(drop=True)
    dec=dec[dec.dt.year>=2004]
    # ★연장: 두 신규 결정일 추가 (holding 2026-07, 2026-08)
    extra=pd.to_datetime(EXTRA_DECISIONS)
    dec=pd.concat([pd.Series(dec.values), pd.Series(extra.values)]).drop_duplicates().sort_values().reset_index(drop=True)
    dec=pd.to_datetime(dec)
    print(f"[decisions] n={len(dec)} {str(dec.min())[:10]}..{str(dec.max())[:10]} (extra={EXTRA_DECISIONS})")

    rows=[]
    for year in range(OOS_START_YEAR,2027):
        boundary=np.datetime64(f"{year}-01-01")
        tr_idx=np.where(panel_dates<boundary)[0]
        if len(tr_idx)<500: continue
        mu=Xraw[tr_idx].mean(0); sd=Xraw[tr_idx].std(0); sd[sd<1e-8]=1.0
        Xz=((Xraw-mu)/sd).astype(np.float32)
        seq_end_all=[i for i in tr_idx if i-L+1>=0]
        seq_end_tr=seq_end_all[::STRIDE]
        Wtr,_=make_seq_windows(seq_end_tr, Xz)
        Vtr=Xz[tr_idx]
        if Wtr is None or len(Wtr)<200: continue
        cut=np.datetime64(f"{year-1}-01-01")
        fit_end=[i for i in seq_end_tr if panel_dates[i]<cut]
        val_end=[i for i in seq_end_tr if panel_dates[i]>=cut]
        if len(val_end)<30 or len(fit_end)<200:
            k=int(len(seq_end_tr)*0.85); fit_end=seq_end_tr[:k]; val_end=seq_end_tr[k:]
        Wfit,_=make_seq_windows(fit_end,Xz); Wval,_=make_seq_windows(val_end,Xz)
        Vfit=Xz[[i for i in tr_idx if panel_dates[i]<cut]]; Vval=Xz[[i for i in tr_idx if panel_dates[i]>=cut]]
        if len(Vval)<40: Vfit=Vtr[:int(len(Vtr)*0.85)]; Vval=Vtr[int(len(Vtr)*0.85):]
        seq_ae=train_ae(SeqAE(nfeat), Wfit, Wval, True)
        pt_ae =train_ae(PointAE(nfeat), Vfit, Vval, False)
        e_seq_is=recon_err_seq(seq_ae, Wtr)
        e_pt_daily=recon_err_point(pt_ae, Xz)
        def pt_score_at(end_i):
            lo=max(0,end_i-SMOOTH+1); return float(np.mean(e_pt_daily[lo:end_i+1]))
        e_pt_is=np.array([pt_score_at(i) for i in tr_idx if i>=SMOOTH-1])
        tau_seq=float(np.quantile(e_seq_is, 1.0-M4_FIRE_RATE))
        tau_pt =float(np.quantile(e_pt_is , 1.0-M4_FIRE_RATE))
        yr_dec=dec[dec.dt.year==year]
        for d in yr_dec:
            dd=np.datetime64(pd.Timestamp(d)); valid=np.where(panel_dates<dd)[0]
            if len(valid)<L: continue
            end=valid[-1]
            s_seq=float(recon_err_seq(seq_ae, Xz[end-L+1:end+1][None,:,:])[0])
            s_pt =pt_score_at(end)
            dd_loose=dd+np.timedelta64(FWD*7//5,'D')
            vl=np.where(panel_dates<dd_loose)[0]
            if len(vl)>=L:
                el=vl[-1]; s_seq_l=float(recon_err_seq(seq_ae, Xz[el-L+1:el+1][None,:,:])[0]); s_pt_l=pt_score_at(el)
                lfd_l=pd.Timestamp(panel_dates[el])
            else:
                s_seq_l=np.nan; s_pt_l=np.nan; lfd_l=pd.NaT
            rows.append(dict(decision_date=pd.Timestamp(d), model_year=year,
                             ae_seq=s_seq, ae_pt=s_pt, tau_seq=tau_seq, tau_pt=tau_pt,
                             fire_seq=int(s_seq>tau_seq), fire_pt=int(s_pt>tau_pt),
                             last_feat_date=pd.Timestamp(panel_dates[end]),
                             ae_seq_loose=s_seq_l, ae_pt_loose=s_pt_l,
                             fire_seq_loose=int(s_seq_l>tau_seq) if np.isfinite(s_seq_l) else 0,
                             fire_pt_loose=int(s_pt_l>tau_pt) if np.isfinite(s_pt_l) else 0,
                             last_feat_date_loose=lfd_l))
        print(f"[refit {year}] tau_seq={tau_seq:.4f} tau_pt={tau_pt:.4f} scored={len(yr_dec)}")

    res=pd.DataFrame(rows).sort_values("decision_date").reset_index(drop=True)
    for col in ["seq","pt"]:
        res[f"exposure_{col}"]=np.where(res[f"fire_{col}"]==1,0.70,1.00)
    res.to_parquet(OUT,index=False)
    print(f"[out] {OUT} rows={len(res)}")
    bad=int((res["last_feat_date"]>=res["decision_date"]).sum())
    print(f"[PIT self-check] last_feat_date>=decision_date: {bad} (must be 0)")
    # ★연장 결정 결과 출력
    print("\n=== 연장 결정 (holding = decision월+1) ===")
    tail=res[res["decision_date"]>=pd.Timestamp("2026-01-01")][
        ["decision_date","ae_seq","tau_seq","fire_seq","ae_seq_loose","fire_seq_loose","last_feat_date"]]
    for _,r in tail.iterrows():
        print(f"  dec={str(r['decision_date'])[:10]} ae_seq={r['ae_seq']:.3f} tau={r['tau_seq']:.3f} "
              f"FIRE={int(r['fire_seq'])} | loose ae={r['ae_seq_loose']:.3f} fire={int(r['fire_seq_loose'])} "
              f"| last_feat={str(r['last_feat_date'])[:10]}")

if __name__=="__main__":
    main()
