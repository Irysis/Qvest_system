"""WT-D20260718_005 — From-scratch factor-timing Transformer (self-attention over 6 family tokens).
Faithful to hypothesis: attention learns factor relationships (co-movement/rotation) from factor
valuation + return-sequence features -> time-varying family weights theta_t.
Discipline: walk-forward expanding refit, PIT target cutoff, train-only standardization, seed>=3.
Output: OOS theta panel (per seed + ensemble) consumed by R canonical_screen_bt paired A/B.
"""
import json, sys
import numpy as np, pandas as pd
import torch, torch.nn as nn

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  = f"{ROOT}/04_Research/method_frontier/wt005_factor_timing"
FAMS = ["value","quality","momentum","low_vol","size","dividend"]
FEATS = ["tr_1m","tr_3m","tr_6m","tr_12m","tr_vol12","val_spread","vs_z"]
WARMUP = 60          # initial train months before first OOS prediction (~2010)
REFIT  = 12          # refit cadence (months)
SEEDS  = [0,1,2]
EPOCHS = 120
BETA   = 2.0         # theta = softmax(BETA * zscore(pred_return)) — matches simple-rule temperature

df = pd.read_parquet(f"{OUT}/family_feature_panel.parquet")
df["date"] = pd.to_datetime(df["date"])
# keep dates where all 6 families have complete features + target
piv = {}
dates = sorted(df["date"].unique())
X = {}; Y = {}
for d in dates:
    sub = df[df["date"]==d].set_index("family")
    if not all(f in sub.index for f in FAMS): continue
    fv = sub.loc[FAMS, FEATS].values.astype("float32")
    yv = sub.loc[FAMS, "fwd_ret"].values.astype("float32")
    if np.isnan(fv).any() or np.isnan(yv).any(): continue
    X[d] = fv; Y[d] = yv
good = sorted(X.keys())
print(f"[data] usable months={len(good)} range {good[0].date()}..{good[-1].date()}")

class FactorTransformer(nn.Module):
    def __init__(self, n_feat, d=16, heads=2, layers=2):
        super().__init__()
        self.inp = nn.Linear(n_feat, d)
        self.fam_emb = nn.Parameter(torch.randn(len(FAMS), d)*0.1)
        enc = nn.TransformerEncoderLayer(d_model=d, nhead=heads, dim_feedforward=2*d,
                                         dropout=0.1, batch_first=True)
        self.enc = nn.TransformerEncoder(enc, num_layers=layers)
        self.head = nn.Linear(d, 1)
    def forward(self, x):           # x: (B, 6, n_feat)
        h = self.inp(x) + self.fam_emb.unsqueeze(0)
        h = self.enc(h)
        return self.head(h).squeeze(-1)   # (B, 6) predicted std fwd return

def train_block(train_dates, seed):
    torch.manual_seed(seed); np.random.seed(seed)
    Xtr = np.stack([X[d] for d in train_dates])          # (N,6,F)
    Ytr = np.stack([Y[d] for d in train_dates])          # (N,6)
    # PIT standardization from TRAIN only (per-feature, over N*6)
    mu = Xtr.reshape(-1, Xtr.shape[-1]).mean(0); sd = Xtr.reshape(-1, Xtr.shape[-1]).std(0)+1e-6
    ymu = Ytr.mean(); ysd = Ytr.std()+1e-6
    Xn = (Xtr - mu)/sd; Yn = (Ytr - ymu)/ysd
    xt = torch.tensor(Xn); yt = torch.tensor(Yn)
    model = FactorTransformer(len(FEATS))
    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-3)
    lossf = nn.MSELoss()
    model.train()
    for ep in range(EPOCHS):
        opt.zero_grad(); pred = model(xt); loss = lossf(pred, yt); loss.backward(); opt.step()
    return model, (mu, sd)

def predict(model, stats, d):
    mu, sd = stats
    xn = (X[d]-mu)/sd
    model.eval()
    with torch.no_grad():
        p = model(torch.tensor(xn[None,...])).numpy()[0]   # (6,)
    return p

# walk-forward
rows_all = {s: [] for s in SEEDS}
first_test = WARMUP
i = first_test
while i < len(good):
    c = i
    train_dates = good[:c]                       # targets realized <= good[c-1] < test start good[c] (PIT)
    if len(train_dates) < 36: i += REFIT; continue
    test_dates = good[c:c+REFIT]
    for s in SEEDS:
        model, stats = train_block(train_dates, s)
        for d in test_dates:
            p = predict(model, stats, d)
            z = (p - p.mean())/(p.std()+1e-9)
            w = np.exp(BETA*z); w = w/w.sum()
            for k,fk in enumerate(FAMS):
                rows_all[s].append((d, fk, float(w[k]), float(p[k])))
    i += REFIT

# save per-seed + ensemble (mean predicted return -> softmax)
seed_dfs = {}
for s in SEEDS:
    t = pd.DataFrame(rows_all[s], columns=["date","family","theta","pred"])
    t.to_parquet(f"{OUT}/theta_transformer_seed{s}.parquet", index=False)
    seed_dfs[s] = t
# ensemble on pred
merged = seed_dfs[SEEDS[0]][["date","family","pred"]].rename(columns={"pred":"p0"})
for j,s in enumerate(SEEDS[1:],1):
    merged = merged.merge(seed_dfs[s][["date","family","pred"]].rename(columns={"pred":f"p{j}"}),
                          on=["date","family"])
pcols = [c for c in merged.columns if c.startswith("p")]
merged["pred_ens"] = merged[pcols].mean(axis=1)
ens_rows=[]
for d, g in merged.groupby("date"):
    p = g["pred_ens"].values; fam = g["family"].values
    z = (p-p.mean())/(p.std()+1e-9); w = np.exp(BETA*z); w=w/w.sum()
    for fk,wi,pi in zip(fam,w,p): ens_rows.append((d,fk,float(wi),float(pi)))
ens = pd.DataFrame(ens_rows, columns=["date","family","theta","pred"])
ens.to_parquet(f"{OUT}/theta_transformer_ensemble.parquet", index=False)

oos_start = good[first_test]
meta = dict(usable_months=len(good), oos_start=str(oos_start.date()),
            oos_months=int(len(good)-first_test), warmup=WARMUP, refit=REFIT,
            seeds=SEEDS, epochs=EPOCHS, beta=BETA, d_model=16, heads=2, layers=2,
            n_feat=len(FEATS), features=FEATS)
json.dump(meta, open(f"{OUT}/transformer_meta.json","w"), indent=1)
print("[done] OOS start", oos_start.date(), "oos_months", len(good)-first_test)
# quick per-seed theta dispersion diagnostic
disp = np.std([seed_dfs[s].groupby("family")["theta"].mean().values for s in SEEDS], axis=0)
print("[seed theta dispersion per family mean-theta]", dict(zip(FAMS, np.round(disp,4))))
print("[ensemble mean theta per family]", ens.groupby("family")["theta"].mean().round(3).to_dict())
