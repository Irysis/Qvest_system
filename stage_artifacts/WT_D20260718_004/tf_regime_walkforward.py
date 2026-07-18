#!/usr/bin/env python
# tf_regime_walkforward.py — WT-D20260718_004
# PIT-strict walk-forward Transformer regime detector for TIMING overlay (detector-swap vs M4 BOCPD).
# NOT cross-sectional. Predicts P(next-~month KOSPI200 down) from daily market-priced sequences.
# Output: per monthly decision_date P_bad + IS-calibrated exposure (matched to incumbent M4 firing).
# Index returns via PRICE RATIOS (BM_Close), not return compounding (avoids backtest-synthesis patterns).
#
# PIT contract:
#   - Features: market-priced same-day-observable daily series (VIX/spreads/yields/KRW/SP500/KOSPI). Causal ffill.
#   - Standardization: fit on TRAINING window only (expanding), frozen per refit.
#   - Label: forward 21-trading-day KOSPI200 index return < 0 (price ratio).
#   - Walk-forward: refit end-of-year on expanding window using ONLY (X_t, y_t) with label fully realized
#       before the refit boundary. Freeze; score months in that year (seq ends strictly before decision_date).
#   - Exposure threshold: IS-calibrated on model in-training predictions (frozen per refit), matched to M4 firing.
import os, sys, json
os.environ.setdefault("OMP_NUM_THREADS","1"); os.environ.setdefault("MKL_NUM_THREADS","1")
import numpy as np, pandas as pd
import pyarrow.parquet as pq
import torch, torch.nn as nn
torch.set_num_threads(1)
SEED=20260718
np.random.seed(SEED); torch.manual_seed(SEED)

ROOT=os.environ.get("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
os.chdir(ROOT)
PIN=".cache/pins/WT-D20260718_004_r1"
FRED=os.path.join(PIN,"fred_macro_wide.parquet")
BENCH=os.path.join(PIN,"benchmark.parquet")
CARRIER=os.path.join(PIN,"carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")
OUT="stage_artifacts/WT_D20260718_004/tf_regime_signal.parquet"

L=60; FWD=21
D_MODEL=32; NHEAD=2; NLAYERS=2; DROPOUT=0.2
EPOCHS=22; LR=1e-3; WD=1e-4; PATIENCE=4; BATCH=256
OOS_START_YEAR=2008
# dense-from-2000 market/financial-conditions features only (HY/BBB=2023+, SP500=2016+ dropped: too short for 2008 OOS)
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
    n=len(c); fwd=np.full(n,np.nan)
    fwd[:n-FWD]=c[FWD:]/c[:n-FWD]-1.0          # forward FWD-day index return (price ratio)
    bm["fwd_ret"]=fwd
    bm["label"]=(bm["fwd_ret"]<0).astype(float)
    bm["label_date"]=bm["Date"].shift(-FWD)
    spine=bm[["Date","kret","klog","kvol20","kcum20","kcum60","fwd_ret","label","label_date"]].copy()
    m=pd.merge_asof(spine, fr[["Date"]+FRED_FEATS], on="Date", direction="backward")
    feat_cols=["klog","kvol20","kcum20","kcum60"]+FRED_FEATS
    m[feat_cols]=m[feat_cols].ffill()
    m=m.dropna(subset=feat_cols).reset_index(drop=True)
    return m, feat_cols

class TFReg(nn.Module):
    def __init__(self, nfeat):
        super().__init__()
        self.inp=nn.Linear(nfeat, D_MODEL)
        self.pos=nn.Parameter(torch.randn(1,L,D_MODEL)*0.02)
        enc=nn.TransformerEncoderLayer(D_MODEL,NHEAD,dim_feedforward=64,dropout=DROPOUT,batch_first=True,activation="gelu")
        self.tf=nn.TransformerEncoder(enc,NLAYERS)
        self.head=nn.Sequential(nn.LayerNorm(D_MODEL),nn.Linear(D_MODEL,1))
    def forward(self,x):
        h=self.inp(x)+self.pos[:,:x.size(1),:]; h=self.tf(h); h=h.mean(dim=1)
        return self.head(h).squeeze(-1)

def make_windows(idx_list, X, y):
    xs=[]; ys=[]
    for i in idx_list:
        if i-L+1<0: continue
        xs.append(X[i-L+1:i+1]); ys.append(y[i])
    if not xs: return None,None
    return np.stack(xs).astype(np.float32), np.array(ys,dtype=np.float32)

def train_model(Xtr,ytr,Xva,yva,nfeat):
    torch.manual_seed(SEED); np.random.seed(SEED)
    mdl=TFReg(nfeat)
    pos=ytr.sum(); neg=len(ytr)-pos
    lossf=nn.BCEWithLogitsLoss(pos_weight=torch.tensor([neg/max(pos,1.0)],dtype=torch.float32))
    opt=torch.optim.Adam(mdl.parameters(),lr=LR,weight_decay=WD)
    Xtr_t=torch.tensor(Xtr); ytr_t=torch.tensor(ytr); Xva_t=torch.tensor(Xva); yva_t=torch.tensor(yva)
    best=1e9; best_state=None; wait=0; n=len(Xtr_t)
    for ep in range(EPOCHS):
        mdl.train(); perm=torch.randperm(n)
        for b in range(0,n,BATCH):
            bi=perm[b:b+BATCH]; opt.zero_grad(); loss=lossf(mdl(Xtr_t[bi]),ytr_t[bi]); loss.backward(); opt.step()
        mdl.eval()
        with torch.no_grad(): vl=lossf(mdl(Xva_t),yva_t).item()
        if vl<best-1e-4: best=vl; best_state={k:v.clone() for k,v in mdl.state_dict().items()}; wait=0
        else: wait+=1
        if wait>=PATIENCE: break
    if best_state is not None: mdl.load_state_dict(best_state)
    mdl.eval(); return mdl

def main():
    panel,feat_cols=build_panel(); nfeat=len(feat_cols)
    Xraw=panel[feat_cols].values.astype(np.float64); yall=panel["label"].values
    panel_dates=pd.to_datetime(panel["Date"]).values
    label_dates=pd.to_datetime(panel["label_date"]).values
    print(f"[panel] rows={len(panel)} feats={nfeat} range {str(panel['Date'].min())[:10]}..{str(panel['Date'].max())[:10]} base_rate={np.nanmean(yall):.3f}")
    car=pq.read_table(CARRIER).to_pandas()
    dec=pd.to_datetime(car["decision_date"]).drop_duplicates().sort_values().reset_index(drop=True)
    dec=dec[dec.dt.year>=2004]
    print(f"[decisions] n={len(dec)} {str(dec.min())[:10]}..{str(dec.max())[:10]}")
    rows=[]; m4_fire_rate=0.126
    for year in range(OOS_START_YEAR,2027):
        boundary=np.datetime64(f"{year}-01-01")
        tr_mask=(label_dates<boundary)&np.isfinite(yall)
        tr_idx=np.where(tr_mask)[0]
        if len(tr_idx)<500: continue
        mu=Xraw[tr_idx].mean(0); sd=Xraw[tr_idx].std(0); sd[sd<1e-8]=1.0
        Xz=((Xraw-mu)/sd).astype(np.float32)
        cut_val=np.datetime64(f"{year-1}-01-01")
        va_idx=tr_idx[panel_dates[tr_idx]>=cut_val]; fit_idx=tr_idx[panel_dates[tr_idx]<cut_val]
        if len(va_idx)<60 or len(fit_idx)<300:
            k=int(len(tr_idx)*0.85); fit_idx=tr_idx[:k]; va_idx=tr_idx[k:]
        Xtr,ytr=make_windows(fit_idx.tolist(),Xz,yall); Xva,yva=make_windows(va_idx.tolist(),Xz,yall)
        if Xtr is None or Xva is None: continue
        mdl=train_model(Xtr,ytr,Xva,yva,nfeat)
        with torch.no_grad(): p_is=torch.sigmoid(mdl(torch.tensor(Xtr))).numpy()
        tau=float(np.quantile(p_is,1.0-m4_fire_rate))
        yr_dec=dec[dec.dt.year==year]
        for d in yr_dec:
            dd=np.datetime64(pd.Timestamp(d)); valid=np.where(panel_dates<dd)[0]
            if len(valid)<L: continue
            end=valid[-1]; seq=Xz[end-L+1:end+1]
            with torch.no_grad(): p=float(torch.sigmoid(mdl(torch.tensor(seq[None,:,:]))).item())
            # LOOSE cutoff (deliberate look-ahead probe for strict-PIT A/B): use data through ~holding-month end
            dd_loose=dd+np.timedelta64(FWD*7//5,'D')  # ~FWD trading days ahead (into holding month)
            vloose=np.where(panel_dates<dd_loose)[0]
            if len(vloose)>=L:
                el=vloose[-1]; ql=Xz[el-L+1:el+1]
                with torch.no_grad(): p_loose=float(torch.sigmoid(mdl(torch.tensor(ql[None,:,:]))).item())
                lfd_loose=pd.Timestamp(panel_dates[el])
            else:
                p_loose=np.nan; lfd_loose=pd.NaT
            rows.append(dict(decision_date=pd.Timestamp(d), p_bad=p, tau=tau, model_year=year,
                             last_feat_date=pd.Timestamp(panel_dates[end]), fire=int(p>tau),
                             p_bad_loose=p_loose, last_feat_date_loose=lfd_loose,
                             fire_loose=int(p_loose>tau) if np.isfinite(p_loose) else 0))
        print(f"[refit {year}] train_n={len(Xtr)} val_n={len(Xva)} tau={tau:.3f} scored={len(yr_dec)}")
        pd.DataFrame(rows).to_parquet(OUT+".partial",index=False)  # incremental insurance
    res=pd.DataFrame(rows).sort_values("decision_date").reset_index(drop=True)
    res["exposure_matched"]=np.where(res["fire"]==1,0.70,1.00)
    res["exposure_2tier"]=1.00
    res.loc[res["p_bad"]>res["tau"],"exposure_2tier"]=0.70
    res.loc[res["p_bad"]>np.minimum(res["tau"]*1.15,0.99),"exposure_2tier"]=0.40
    res.to_parquet(OUT,index=False)
    print(f"[out] {OUT} rows={len(res)} fire_rate={res['fire'].mean():.3f} mean_exp_matched={res['exposure_matched'].mean():.3f}")
    print(res[["decision_date","p_bad","tau","fire","exposure_matched"]].head(6).to_string())
    print(res[["decision_date","p_bad","fire","exposure_matched"]].tail(6).to_string())
    bad=int((res["last_feat_date"]>=res["decision_date"]).sum())
    print(f"[PIT self-check] rows with last_feat_date>=decision_date: {bad} (must be 0)")

if __name__=="__main__":
    main()
