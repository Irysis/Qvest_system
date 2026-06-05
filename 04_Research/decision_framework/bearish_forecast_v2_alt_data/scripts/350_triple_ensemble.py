#!/usr/bin/env python3
"""350_triple_ensemble.py — HGB + TimeMAE + Andreou options triple ensemble

Findings synthesis:
  HGB V1:        2018-20 1.93x, 2021-23 2.41x, 2024-26 1.17x, Full 2.00x
  TimeMAE:       2018-20 0.92x, 2021-23 1.22x, 2024-26 4.18x, Full 1.38x  cor_hgb=0.021
  Andreou opt:   2018-20 1.81x, 2021-23 1.17x, 2024-26 2.35x, Full 1.25x  cor_hgb=TBD
  Hamilton MS dropped (cor=0.809 with HGB, worse everywhere)

Triple ensemble variants:
  T1: 1/3 each
  T2: 1/2 HGB + 1/4 TimeMAE + 1/4 Andreou (HGB-heavy)
  T3: 2/5 HGB + 2/5 TimeMAE + 1/5 Andreou
  T4: 1/3 + 2/3 max(TimeMAE, Andreou)  — HGB always + best 2024-26 signal
  T5: regime-aware — HGB primary, switch to TimeMAE/Andreou when their conf high

Output: outputs/04_evaluation/cycle58dd_phase3_triple_ensemble.json
"""
import json
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
EVAL = WS / "outputs/04_evaluation"
OUT = EVAL / "cycle58dd_phase3_triple_ensemble.json"

# Load all 3 model predictions (saved as JSON predictions dict)
def load_preds(path, key='predictions'):
    j = json.loads(Path(path).read_text())
    p_dict = j.get(key, {})
    # date str → float
    return {pd.Timestamp(k): float(v) for k, v in p_dict.items()}


# Andreou saved predictions
andreou_json = json.loads((EVAL / "cycle58dd_phase3_3_andreou.json").read_text())
andreou_preds = {pd.Timestamp(k): float(v) for k, v in andreou_json['predictions'].items()}
print(f"[Load Andreou] {len(andreou_preds)} predictions")


# Rebuild HGB V1 + TimeMAE predictions (these scripts don't save predictions)
# Use the data pipeline from 322 (HGB + TimeMAE ensemble)
import os
os.environ['CUBLAS_WORKSPACE_CONFIG'] = ':4096:8'
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from sklearn.ensemble import HistGradientBoostingClassifier

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)
print(f"[Device] {DEVICE}")

TEST_START = pd.Timestamp("2018-01-01")
SEQ_LEN = 21
PRETRAIN_PATH = WS / "outputs/03_models/timemae_pretrain_v1.pt"
ckpt = torch.load(PRETRAIN_PATH, map_location=DEVICE, weights_only=False)
cfg = ckpt['config']
feat_cols = ckpt['feature_cols']
mu = np.array(ckpt['feature_mu']); sd = np.array(ckpt['feature_sd'])


class TimeMAEEncoder(nn.Module):
    def __init__(self, n_features, d_model, n_heads, n_layers, dropout, seq_len):
        super().__init__()
        self.input_proj = nn.Linear(n_features, d_model)
        self.input_norm = nn.LayerNorm(d_model)
        self.pos_emb = nn.Parameter(torch.zeros(1, seq_len, d_model))
        self.mask_token = nn.Parameter(torch.zeros(1, 1, d_model))
        layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4, dropout=dropout, batch_first=True,
            activation='gelu', norm_first=True)
        self.encoder = nn.TransformerEncoder(layer, num_layers=n_layers)
        self.enc_norm = nn.LayerNorm(d_model)
        self.recon_head = nn.Sequential(
            nn.Linear(d_model, d_model * 2), nn.GELU(), nn.Dropout(dropout),
            nn.Linear(d_model * 2, n_features))
    def encode(self, x):
        h = self.input_proj(x); h = self.input_norm(h); h = h + self.pos_emb
        h = self.encoder(h); h = self.enc_norm(h)
        return h

class BearClassifier(nn.Module):
    def __init__(self, encoder, d_model, dropout=0.20):
        super().__init__()
        self.encoder = encoder; self.dropout = nn.Dropout(dropout)
        self.head = nn.Sequential(
            nn.LayerNorm(d_model), nn.Linear(d_model, d_model // 2),
            nn.GELU(), nn.Dropout(dropout), nn.Linear(d_model // 2, 1))
    def forward(self, x):
        h = self.encoder.encode(x); h = h.mean(dim=1); h = self.dropout(h)
        return self.head(h).squeeze(-1)


# Load data
print(f"\n[Build] HGB + TimeMAE walk-forward predictions")
DATA = WS / "outputs/01_data"
feat = pd.read_parquet(DATA / "feature_panel_v5g_cross_market.parquet")
feat['Date'] = pd.to_datetime(feat['Date']); feat = feat.sort_values('Date').reset_index(drop=True)
feat[feat_cols] = feat[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
feat[feat_cols] = (feat[feat_cols] - mu) / sd
feat_X = feat[feat_cols].values

m = pd.read_parquet(DATA / "monthly_features.parquet")
m['Date'] = pd.to_datetime(m['Date'])
m = m.dropna(subset=['y_tail_q15']).reset_index(drop=True)
m_feat_cols = [c for c in m.columns if c not in ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']]
m[m_feat_cols] = m[m_feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)

seqs = []; ys = []; dates = []; m_rows = []
for _, row in m.iterrows():
    ms = row['Date']; cut = ms - pd.Timedelta(days=1)
    cut_idx = (feat['Date'] <= cut).sum() - 1
    if cut_idx + 1 < SEQ_LEN: continue
    seq = feat_X[cut_idx - SEQ_LEN + 1 : cut_idx + 1]
    if seq.shape != (SEQ_LEN, len(feat_cols)): continue
    seqs.append(seq); ys.append(row['y_tail_q15']); dates.append(ms)
    m_rows.append(row[m_feat_cols].values)
X_seq = np.array(seqs, dtype=np.float32); y = np.array(ys, dtype=np.float32)
X_mon = np.array(m_rows, dtype=np.float32)
dates = pd.to_datetime(dates)
test_mask = dates >= TEST_START; test_idx = np.where(test_mask)[0]
print(f"  total {len(X_seq)} sequences, OOS {len(test_idx)} months")

# HGB monthly expanding
print("\n[HGB monthly expanding]")
p_hgb = []; y_hgb = []; d_hgb = []
for i in test_idx:
    tr = np.arange(0, i)
    if y[tr].sum() < 20: continue
    mh = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
        class_weight='balanced', random_state=42)
    mh.fit(X_mon[tr], y[tr])
    p_hgb.append(mh.predict_proba(X_mon[i:i+1])[0, 1])
    y_hgb.append(y[i]); d_hgb.append(dates[i])
p_hgb = np.array(p_hgb); y_hgb = np.array(y_hgb); d_hgb = pd.to_datetime(d_hgb)

# TimeMAE annual retrain
print("\n[TimeMAE annual retrain]")
def fine_tune(X_tr, y_tr, epochs=30, lr=5e-4):
    enc = TimeMAEEncoder(n_features=cfg['n_features'], d_model=cfg['d_model'],
                          n_heads=cfg['n_heads'], n_layers=cfg['n_layers'],
                          dropout=cfg['dropout'], seq_len=cfg['seq_len']).to(DEVICE)
    enc.load_state_dict(ckpt['state_dict'], strict=True)
    model = BearClassifier(enc, d_model=cfg['d_model']).to(DEVICE)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=torch.tensor([min(pos_w, 8.0)], device=DEVICE))
    Xt = torch.from_numpy(X_tr).to(DEVICE); yt = torch.from_numpy(y_tr).to(DEVICE)
    loader = DataLoader(TensorDataset(Xt, yt), batch_size=64, shuffle=True, drop_last=False)
    for _ in range(epochs):
        model.train()
        for xb, yb in loader:
            opt.zero_grad(); loss = loss_fn(model(xb), yb)
            loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
        sched.step()
    return model

def predict_t(model, X):
    model.eval()
    with torch.no_grad():
        return torch.sigmoid(model(torch.from_numpy(X).to(DEVICE))).cpu().numpy()

test_dates_s = pd.Series(dates[test_idx])
years = sorted(test_dates_s.dt.year.unique())
p_tmae_all = np.full(len(test_idx), np.nan)
for yr in years:
    yr_mask = test_dates_s.dt.year == yr
    yr_pos = np.where(yr_mask.values)[0]
    if len(yr_pos) == 0: continue
    first_global = test_idx[yr_pos[0]]
    tr_idx = np.arange(0, first_global)
    if y[tr_idx].sum() < 20: continue
    model = fine_tune(X_seq[tr_idx], y[tr_idx])
    p_tmae_all[yr_pos] = predict_t(model, X_seq[test_idx[yr_pos]])

# Align all 3 to common dates
common_dates = pd.Series(d_hgb)
tmae_align = np.full(len(common_dates), np.nan)
andreou_align = np.full(len(common_dates), np.nan)
for i, d in enumerate(common_dates):
    # TimeMAE
    test_pos = np.where(test_dates_s.values == d.to_numpy())[0]
    if len(test_pos) > 0:
        tmae_align[i] = p_tmae_all[test_pos[0]]
    # Andreou
    if d in andreou_preds:
        andreou_align[i] = andreou_preds[d]

# Filter to all three available
mask = ~np.isnan(tmae_align) & ~np.isnan(andreou_align)
p_hgb_f = p_hgb[mask]; p_tmae_f = tmae_align[mask]; p_andr_f = andreou_align[mask]
y_f = y_hgb[mask]; dates_f = pd.Series(d_hgb)[mask].reset_index(drop=True)
n = len(y_f); base = y_f.mean()
print(f"\n[Aligned] n={n}, base={base*100:.1f}%")

# Individual
results = {}
for name, p in [('HGB', p_hgb_f), ('TimeMAE', p_tmae_f), ('Andreou_opt', p_andr_f)]:
    pr = average_precision_score(y_f, p)
    roc = roc_auc_score(y_f, p)
    results[name] = {'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc)}
    print(f"  {name:<14s} PR-AUC {pr:.4f} lift {pr/base:.2f}x ROC {roc:.4f}")

# Correlations
print(f"\n  cor(HGB, TimeMAE)     = {np.corrcoef(p_hgb_f, p_tmae_f)[0, 1]:+.3f}")
print(f"  cor(HGB, Andreou)     = {np.corrcoef(p_hgb_f, p_andr_f)[0, 1]:+.3f}")
print(f"  cor(TimeMAE, Andreou) = {np.corrcoef(p_tmae_f, p_andr_f)[0, 1]:+.3f}")

# Triple ensemble variants
print("\n[Triple ensemble variants — vs y_tail_q15]")
ens = {
    'HGB_only': p_hgb_f,
    'TimeMAE_only': p_tmae_f,
    'Andreou_only': p_andr_f,
    'T1_eq_third': (p_hgb_f + p_tmae_f + p_andr_f) / 3,
    'T2_hgb_heavy_1/2': 0.5 * p_hgb_f + 0.25 * p_tmae_f + 0.25 * p_andr_f,
    'T3_2/5_2/5_1/5': 0.4 * p_hgb_f + 0.4 * p_tmae_f + 0.2 * p_andr_f,
    'T4_hgb_plus_max_others': (p_hgb_f + np.maximum(p_tmae_f, p_andr_f)) / 2,
    'T5_hgb_2/3_max_others_1/3': 2/3 * p_hgb_f + 1/3 * np.maximum(p_tmae_f, p_andr_f),
}
for name, p in ens.items():
    pr = average_precision_score(y_f, p)
    flag = '⭐' if pr > results['HGB']['pr_auc'] else ''
    print(f"  {name:<28s} PR-AUC {pr:.4f} lift {pr/base:.2f}x {flag}")
    results[name] = {'pr_auc': float(pr), 'lift': float(pr / base)}

# Period-balanced
print("\n[Period-balanced]")
periods = [('2018-2020', '2018-01-01', '2020-12-31'),
           ('2021-2023', '2021-01-01', '2023-12-31'),
           ('2024-2026', '2024-01-01', '2026-12-31')]
print(f"{'Variant':<28s} {'2018-20':>10s} {'2021-23':>10s} {'2024-26':>10s}")
period_results = {}
for name, p in ens.items():
    row = {}
    for pname, s, e in periods:
        mask_p = ((dates_f >= pd.Timestamp(s)) & (dates_f <= pd.Timestamp(e))).values
        if mask_p.sum() < 12 or y_f[mask_p].sum() < 2:
            row[pname] = 'N/A'
        else:
            pr = average_precision_score(y_f[mask_p], p[mask_p])
            bp = y_f[mask_p].mean()
            row[pname] = f"{pr/bp:.2f}x"
    period_results[name] = row
    print(f"  {name:<28s} {row['2018-2020']:>10s} {row['2021-2023']:>10s} {row['2024-2026']:>10s}")

# Best ensemble paired bootstrap vs HGB
ens_only = {k: v for k, v in results.items() if k.startswith('T')}
best_k = max(ens_only.keys(), key=lambda k: ens_only[k]['pr_auc'])
print(f"\n[Paired bootstrap CI 95% — {best_k} vs HGB, B=5000]")
B = 5000; np.random.seed(42)
prs_base = []; prs_best = []; deltas = []
p_best = ens[best_k]
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_f[idx].sum() < 5: continue
    pr_b = average_precision_score(y_f[idx], p_hgb_f[idx])
    pr_e = average_precision_score(y_f[idx], p_best[idx])
    prs_base.append(pr_b); prs_best.append(pr_e); deltas.append(pr_e - pr_b)
prs_base = np.array(prs_base); prs_best = np.array(prs_best); deltas = np.array(deltas)
print(f"  HGB CI:        [{np.quantile(prs_base, 0.025):.4f}, {np.quantile(prs_base, 0.975):.4f}]")
print(f"  {best_k} CI:  [{np.quantile(prs_best, 0.025):.4f}, {np.quantile(prs_best, 0.975):.4f}]")
print(f"  Delta CI:      [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
print(f"  P(triple > HGB) = {(deltas > 0).mean():.3f}")
print(f"  P(triple lift > 2x) = {(prs_best > 2*base).mean():.3f}")
print(f"  P(HGB lift > 2x) = {(prs_base > 2*base).mean():.3f}")

audit = {
    'cycle': '58DD_phase3_triple_ensemble',
    'n': int(n), 'base': float(base),
    'individual_results': results,
    'period_balanced': period_results,
    'correlations': {
        'hgb_timemae': float(np.corrcoef(p_hgb_f, p_tmae_f)[0, 1]),
        'hgb_andreou': float(np.corrcoef(p_hgb_f, p_andr_f)[0, 1]),
        'tmae_andreou': float(np.corrcoef(p_tmae_f, p_andr_f)[0, 1]),
    },
    'best_ensemble': best_k,
    'paired_bootstrap_best_vs_hgb': {
        'hgb_ci': [float(np.quantile(prs_base, 0.025)), float(np.quantile(prs_base, 0.975))],
        'best_ci': [float(np.quantile(prs_best, 0.025)), float(np.quantile(prs_best, 0.975))],
        'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
        'p_best_gt_hgb': float((deltas > 0).mean()),
        'p_best_lift_gt_2x': float((prs_best > 2*base).mean()),
    },
}
OUT.write_text(json.dumps(audit, indent=2))
print(f"\nSaved: {OUT}")
