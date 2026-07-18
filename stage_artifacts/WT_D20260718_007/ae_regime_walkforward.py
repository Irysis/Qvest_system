#!/usr/bin/env python
# ae_regime_walkforward.py — WT-D20260718_007
# UNSUPERVISED sequence/point autoencoder regime detector for a TIMING overlay (detector-swap vs M4 BOCPD).
# Root-cause attack on WT-004: supervised transformer MISSED 2008/COVID/2022 (OOD crashes need in-sample analog).
# An autoencoder learns "normal" market dynamics and flags DEVIATION (high reconstruction error) — a crash need
# NEVER appear in training to be flagged as anomalous. NO labels -> the OOD problem is structurally avoided.
#
# PIT contract (walk-forward, no label needed -> even cleaner than WT-004):
#   - Features: same 11 market-priced same-day-observable daily series as WT-004 (KOSPI ret/vol/mom + 7 FRED).
#   - "Normal" learned on TRAINING window only (expanding, annual refit); refit uses windows ending strictly
#     before the year boundary. Standardization mu/sd frozen on training window.
#   - Threshold tau: IS-calibrated on TRAINING-window reconstruction errors at quantile(1 - m4_fire_rate),
#     matched to incumbent M4 firing frequency (0.126) and depth (0.70) -> isolates TIMING quality, not de-risk budget.
#   - Score each monthly decision_date: sequence/day ends strictly before holding-month start (last_feat_date < decision_date).
#   - LOOSE probe (deliberate look-ahead) for strict-PIT A/B: reconstruct using data through ~holding-month end.
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
OUT="stage_artifacts/WT_D20260718_007/ae_regime_signal.parquet"

L=60; FWD=21; SMOOTH=21           # seq window, forward trading days (loose probe), point-AE trailing smoother
STRIDE=3                          # training seq-window stride: consecutive 60d windows ~98% overlap -> near-lossless 3x speedup
D_HID=16; D_LAT=8; DROPOUT=0.1
EPOCHS=25; LR=1e-3; WD=1e-4; PATIENCE=4; BATCH=256
OOS_START_YEAR=2008
M4_FIRE_RATE=0.126                # incumbent M4 firing frequency (layer5 m4_weight_lag<1 = 0.1264) -> exposure match
FRED_FEATS=["VIX","Term_Spread","KRW_USD","US_10Y_Yield","US_2Y_Yield","StL_Fin_Stress","Chi_Fin_Cond"]

# ------------------------------------------------------------------ panel (identical to WT-004 build_panel; no label used) ----
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

# ------------------------------------------------------------------ models ----
class SeqAE(nn.Module):
    """LSTM sequence autoencoder: reconstruct the whole L-day window of features. Anomaly = mean recon MSE."""
    def __init__(self, nfeat):
        super().__init__()
        self.enc=nn.LSTM(nfeat, D_HID, batch_first=True)
        self.to_lat=nn.Linear(D_HID, D_LAT)
        self.from_lat=nn.Linear(D_LAT, D_HID)
        self.dec=nn.LSTM(D_HID, D_HID, batch_first=True)
        self.out=nn.Linear(D_HID, nfeat)
        self.drop=nn.Dropout(DROPOUT)
    def forward(self,x):
        _,(h,_)=self.enc(x)                    # h: (1,B,D_HID)
        z=self.to_lat(self.drop(h[-1]))        # (B,D_LAT)
        rep=self.from_lat(z).unsqueeze(1).repeat(1,x.size(1),1)  # (B,L,D_HID)
        d,_=self.dec(rep)
        return self.out(d)                     # (B,L,nfeat)

class PointAE(nn.Module):
    """Dense autoencoder on a single day's cross-feature vector. Anomaly = per-vector recon MSE (co-movement anomaly)."""
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
    """W:(B,L,nfeat) -> per-window mean MSE."""
    with torch.no_grad():
        r=model(torch.tensor(W.astype(np.float32)))
        e=((r-torch.tensor(W.astype(np.float32)))**2).mean(dim=(1,2)).numpy()
    return e

def recon_err_point(model, V):
    """V:(B,nfeat) -> per-vector MSE."""
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
    print(f"[decisions] n={len(dec)} {str(dec.min())[:10]}..{str(dec.max())[:10]}")

    rows=[]
    for year in range(OOS_START_YEAR,2027):
        boundary=np.datetime64(f"{year}-01-01")
        tr_idx=np.where(panel_dates<boundary)[0]
        if len(tr_idx)<500: continue
        mu=Xraw[tr_idx].mean(0); sd=Xraw[tr_idx].std(0); sd[sd<1e-8]=1.0
        Xz=((Xraw-mu)/sd).astype(np.float32)
        # ---- training samples end strictly before boundary (strided; overlapping windows near-identical) ----
        seq_end_all=[i for i in tr_idx if i-L+1>=0]
        seq_end_tr=seq_end_all[::STRIDE]
        Wtr,_=make_seq_windows(seq_end_tr, Xz)
        Vtr=Xz[tr_idx]                                   # point vectors in training window
        if Wtr is None or len(Wtr)<200: continue
        # IS-only validation = last ~12mo (~252d) of training window (no OOS peek)
        cut=np.datetime64(f"{year-1}-01-01")
        fit_end=[i for i in seq_end_tr if panel_dates[i]<cut]
        val_end=[i for i in seq_end_tr if panel_dates[i]>=cut]
        if len(val_end)<30 or len(fit_end)<200:
            k=int(len(seq_end_tr)*0.85); fit_end=seq_end_tr[:k]; val_end=seq_end_tr[k:]
        Wfit,_=make_seq_windows(fit_end,Xz); Wval,_=make_seq_windows(val_end,Xz)
        Vfit=Xz[[i for i in tr_idx if panel_dates[i]<cut]]; Vval=Xz[[i for i in tr_idx if panel_dates[i]>=cut]]
        if len(Vval)<40: Vfit=Vtr[:int(len(Vtr)*0.85)]; Vval=Vtr[int(len(Vtr)*0.85):]
        # ---- fit unsupervised AEs ----
        seq_ae=train_ae(SeqAE(nfeat), Wfit, Wval, True)
        pt_ae =train_ae(PointAE(nfeat), Vfit, Vval, False)
        # ---- IS recon-error distribution -> tau matched to M4 fire rate ----
        e_seq_is=recon_err_seq(seq_ae, Wtr)
        # point-AE: smooth per-day error over trailing SMOOTH days for a regime (not day) signal
        e_pt_daily=recon_err_point(pt_ae, Xz)                          # over ALL days (indexing by position)
        # trailing-mean point error at each training END index
        def pt_score_at(end_i):
            lo=max(0,end_i-SMOOTH+1); return float(np.mean(e_pt_daily[lo:end_i+1]))
        e_pt_is=np.array([pt_score_at(i) for i in tr_idx if i>=SMOOTH-1])
        tau_seq=float(np.quantile(e_seq_is, 1.0-M4_FIRE_RATE))
        tau_pt =float(np.quantile(e_pt_is , 1.0-M4_FIRE_RATE))
        # ---- score this year's decisions ----
        yr_dec=dec[dec.dt.year==year]
        for d in yr_dec:
            dd=np.datetime64(pd.Timestamp(d)); valid=np.where(panel_dates<dd)[0]
            if len(valid)<L: continue
            end=valid[-1]
            s_seq=float(recon_err_seq(seq_ae, Xz[end-L+1:end+1][None,:,:])[0])
            s_pt =pt_score_at(end)
            # LOOSE (look-ahead probe): through ~holding-month end
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
        print(f"[refit {year}] seq_tr={len(Wtr)} pt_tr={len(Vtr)} tau_seq={tau_seq:.4f} tau_pt={tau_pt:.4f} scored={len(yr_dec)}")
        pd.DataFrame(rows).to_parquet(OUT+".partial",index=False)

    res=pd.DataFrame(rows).sort_values("decision_date").reset_index(drop=True)
    for col in ["seq","pt"]:
        res[f"exposure_{col}"]=np.where(res[f"fire_{col}"]==1,0.70,1.00)
        res[f"exposure_{col}_loose"]=np.where(res[f"fire_{col}_loose"]==1,0.70,1.00)
    res.to_parquet(OUT,index=False)
    print(f"[out] {OUT} rows={len(res)}")
    print(f"  fire_rate seq={res['fire_seq'].mean():.3f} pt={res['fire_pt'].mean():.3f} (target M4={M4_FIRE_RATE})")
    print(f"  mean_exp seq={res['exposure_seq'].mean():.3f} pt={res['exposure_pt'].mean():.3f}")
    bad_seq=int((res["last_feat_date"]>=res["decision_date"]).sum())
    print(f"[PIT self-check] last_feat_date>=decision_date: {bad_seq} (must be 0)")
    # crisis-window firing (KR crash months) — quick self-report
    for lbl,rng in [("2008GFC",("2008-08","2009-03")),("2011Euro",("2011-08","2011-10")),
                    ("2018sell",("2018-10","2018-12")),("COVID",("2020-02","2020-04")),("2022",("2022-01","2022-10"))]:
        mask=(res["decision_date"]>=pd.Timestamp(rng[0]+"-01"))&(res["decision_date"]<=pd.Timestamp(rng[1]+"-28"))
        sub=res[mask]
        print(f"  [crisis {lbl}] months={len(sub)} fire_seq={int(sub['fire_seq'].sum())} fire_pt={int(sub['fire_pt'].sum())}")

if __name__=="__main__":
    main()
