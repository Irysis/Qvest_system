#!/usr/bin/env python3
"""353_top_n_precision.py — Top N absolute precision (도훈 mandate "Top 10 성공확률")

기준 변경: PR-AUC (avg) → Top N picks의 실제 약세 적중률 (직관적)

OOS n=89 (2018-2026), 실제 약세 15건 (base 16.9%)
각 모델 Top 1/3/5/7/10/12/15/20 picks의 적중 (Precision@K)

Per-period analysis: 2018-2020 / 2021-2023 / 2024-2026 별도 Top N

Output: outputs/04_evaluation/cycle58dd_top_n_precision.json
"""
import os
os.environ['CUBLAS_WORKSPACE_CONFIG'] = ':4096:8'
import json
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from sklearn.ensemble import HistGradientBoostingClassifier
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"
OUT = EVAL / "cycle58dd_top_n_precision.json"
PRETRAIN_DIR = WS / "outputs/03_models/timemae_pretrain_per_year"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)
TEST_START = pd.Timestamp("2018-01-01")
SEQ_LEN = 21
D_MODEL = 64; N_HEADS = 4; N_LAYERS = 2; DROPOUT = 0.10

andreou_json = json.loads((EVAL / "cycle58dd_phase3_3_andreou.json").read_text())
andreou_preds = {pd.Timestamp(k): float(v) for k, v in andreou_json['predictions'].items()}


class TimeMAEEncoder(nn.Module):
    def __init__(self, n_features, d_model=D_MODEL, n_heads=N_HEADS, n_layers=N_LAYERS, dropout=DROPOUT, seq_len=SEQ_LEN):
        super().__init__()
        self.input_proj = nn.Linear(n_features, d_model); self.input_norm = nn.LayerNorm(d_model)
        self.pos_emb = nn.Parameter(torch.zeros(1, seq_len, d_model))
        self.mask_token = nn.Parameter(torch.zeros(1, 1, d_model))
        layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4, dropout=dropout, batch_first=True,
            activation='gelu', norm_first=True)
        self.encoder = nn.TransformerEncoder(layer, num_layers=n_layers); self.enc_norm = nn.LayerNorm(d_model)
        self.recon_head = nn.Sequential(nn.Linear(d_model, d_model * 2), nn.GELU(), nn.Dropout(dropout),
            nn.Linear(d_model * 2, n_features))
    def encode(self, x):
        h = self.input_proj(x); h = self.input_norm(h); h = h + self.pos_emb
        h = self.encoder(h); h = self.enc_norm(h)
        return h

class BearClassifier(nn.Module):
    def __init__(self, encoder, d_model, dropout=0.20):
        super().__init__()
        self.encoder = encoder; self.dropout = nn.Dropout(dropout)
        self.head = nn.Sequential(nn.LayerNorm(d_model), nn.Linear(d_model, d_model // 2),
            nn.GELU(), nn.Dropout(dropout), nn.Linear(d_model // 2, 1))
    def forward(self, x):
        h = self.encoder.encode(x); h = h.mean(dim=1); h = self.dropout(h)
        return self.head(h).squeeze(-1)


# Load
feat = pd.read_parquet(DATA / "feature_panel_v5g_cross_market.parquet")
feat['Date'] = pd.to_datetime(feat['Date']); feat = feat.sort_values('Date').reset_index(drop=True)
feat_cols = [c for c in feat.columns if c != 'Date']
feat[feat_cols] = feat[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
feat_X_raw = feat[feat_cols].values

m = pd.read_parquet(DATA / "monthly_features.parquet")
m['Date'] = pd.to_datetime(m['Date'])
m = m.dropna(subset=['y_tail_q15']).reset_index(drop=True)
m_feat_cols = [c for c in m.columns if c not in ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']]
m[m_feat_cols] = m[m_feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)

seqs_raw = []; ys = []; dates = []; m_rows = []
for _, row in m.iterrows():
    ms = row['Date']; cut = ms - pd.Timedelta(days=1)
    cut_idx = (feat['Date'] <= cut).sum() - 1
    if cut_idx + 1 < SEQ_LEN: continue
    seq = feat_X_raw[cut_idx - SEQ_LEN + 1 : cut_idx + 1]
    if seq.shape != (SEQ_LEN, len(feat_cols)): continue
    seqs_raw.append(seq); ys.append(row['y_tail_q15']); dates.append(ms)
    m_rows.append(row[m_feat_cols].values)
X_seq_raw = np.array(seqs_raw, dtype=np.float32)
X_mon = np.array(m_rows, dtype=np.float32)
y = np.array(ys, dtype=np.float32)
dates = pd.to_datetime(dates)
test_idx = np.where(dates >= TEST_START)[0]

# HGB
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

# Per-year TimeMAE
def fine_tune(state, n_features, X_tr, y_tr, epochs=30):
    enc = TimeMAEEncoder(n_features=n_features).to(DEVICE)
    enc.load_state_dict(state, strict=True)
    model = BearClassifier(enc, d_model=D_MODEL).to(DEVICE)
    opt = torch.optim.AdamW(model.parameters(), lr=5e-4, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=torch.tensor([min(pos_w, 8.0)], device=DEVICE))
    Xt = torch.from_numpy(X_tr).to(DEVICE); yt = torch.from_numpy(y_tr).to(DEVICE)
    loader = DataLoader(TensorDataset(Xt, yt), batch_size=64, shuffle=True, drop_last=False)
    for _ in range(epochs):
        model.train()
        for xb, yb in loader:
            opt.zero_grad(); loss = loss_fn(model(xb), yb)
            loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        sched.step()
    return model
def predict_t(model, X):
    model.eval()
    with torch.no_grad():
        return torch.sigmoid(model(torch.from_numpy(X).to(DEVICE))).cpu().numpy()

test_dates_s = pd.Series(dates[test_idx])
p_tmae_all = np.full(len(test_idx), np.nan)
for yr in sorted(test_dates_s.dt.year.unique()):
    yr_pos = np.where((test_dates_s.dt.year == yr).values)[0]
    if len(yr_pos) == 0: continue
    first_global = test_idx[yr_pos[0]]
    tr_idx = np.arange(0, first_global)
    if y[tr_idx].sum() < 20: continue
    enc_path = PRETRAIN_DIR / f"timemae_pretrain_v2_{yr}.pt"
    if not enc_path.exists(): continue
    ckpt_yr = torch.load(enc_path, map_location=DEVICE, weights_only=False)
    mu_y = np.array(ckpt_yr['mu']); sd_y = np.array(ckpt_yr['sd'])
    X_seq_std = ((X_seq_raw - mu_y) / sd_y).astype(np.float32)
    model = fine_tune(ckpt_yr['state_dict'], len(feat_cols), X_seq_std[tr_idx], y[tr_idx])
    p_tmae_all[yr_pos] = predict_t(model, X_seq_std[test_idx[yr_pos]])

common_dates = pd.Series(d_hgb)
test_dates_arr = test_dates_s.values
tmae_align = np.full(len(common_dates), np.nan)
andr_align = np.full(len(common_dates), np.nan)
for i, d in enumerate(common_dates):
    test_pos = np.where(test_dates_arr == d.to_numpy())[0]
    if len(test_pos) > 0: tmae_align[i] = p_tmae_all[test_pos[0]]
    if d in andreou_preds: andr_align[i] = andreou_preds[d]
mask = ~np.isnan(tmae_align) & ~np.isnan(andr_align)
p_hgb_f = p_hgb[mask]; p_tmae_f = tmae_align[mask]; p_andr_f = andr_align[mask]
y_f = y_hgb[mask].astype(int); d_f = pd.Series(d_hgb)[mask].reset_index(drop=True)
n = len(y_f); base = y_f.mean()

# T5 ensemble
p_t5 = 2/3 * p_hgb_f + 1/3 * np.maximum(p_tmae_f, p_andr_f)

print(f"\n[Setup] OOS n={n}개월, 실제 약세 {int(y_f.sum())}건 (base {base*100:.1f}%)")

# Top N precision
TOP_NS = [1, 2, 3, 5, 7, 10, 12, 15, 20]
def top_n_precision(p, y, N):
    if N > len(y): return None
    order = np.argsort(-p)
    topN_idx = order[:N]
    tp = int(y[topN_idx].sum())
    return {'k': int(N), 'tp': tp, 'fp': int(N - tp),
            'precision': float(tp / N), 'random_baseline': float(N * y.mean() / len(y))}

models = {
    'HGB only': p_hgb_f,
    'PerYear TimeMAE': p_tmae_f,
    'Andreou options': p_andr_f,
    'T5 per-year (production)': p_t5,
}

print("\n=== Top N precision (전체 89개월 OOS) ===")
print(f"{'Model':<28s} ", end='')
for N in TOP_NS: print(f"Top{N:>3d} ", end='')
print()
results_all = {}
for name, p in models.items():
    row = []
    print(f"{name:<28s} ", end='')
    for N in TOP_NS:
        r = top_n_precision(p, y_f, N)
        if r is None: row.append({'k': N, 'precision': None}); print(f"  N/A ", end=''); continue
        row.append(r)
        print(f"{r['tp']:>2d}/{N:<2d} ({r['precision']*100:>3.0f}%) ", end='')
    print()
    results_all[name] = row

# Per-period
periods = [('2018-2020', '2018-01-01', '2020-12-31'),
           ('2021-2023', '2021-01-01', '2023-12-31'),
           ('2024-2026', '2024-01-01', '2026-12-31')]

print("\n=== Per-period Top N precision ===")
period_results = {}
for pname, s, e in periods:
    mask_p = ((d_f >= pd.Timestamp(s)) & (d_f <= pd.Timestamp(e))).values
    n_p = mask_p.sum(); y_p = y_f[mask_p]
    if n_p < 8 or y_p.sum() < 2: continue
    print(f"\n[{pname}] n={n_p}, 실제 약세 {int(y_p.sum())}건 (base {y_p.mean()*100:.1f}%)")
    pr_local = {}
    print(f"{'Model':<28s} ", end='')
    for N in [3, 5, 7, 10]:
        if N > n_p: continue
        print(f"Top{N:>2d} ", end='')
    print()
    for name, p in models.items():
        p_period = p[mask_p]
        print(f"{name:<28s} ", end='')
        rows = []
        for N in [3, 5, 7, 10]:
            if N > n_p: continue
            r = top_n_precision(p_period, y_p, N)
            if r is None: rows.append({'k': N, 'precision': None}); continue
            rows.append(r)
            print(f"{r['tp']}/{N} ({r['precision']*100:.0f}%) ", end='')
        print()
        pr_local[name] = rows
    period_results[pname] = pr_local

# Show actual Top 10 picks with dates + outcomes for T5 (the production model)
print("\n=== T5 per-year (production)의 Top 10 픽 상세 ===")
order = np.argsort(-p_t5)[:10]
print(f"{'Rank':>4s} {'Date':<12s} {'Prob':>7s} {'실제 약세':>10s} {'결과':<10s}")
for rank, idx in enumerate(order, 1):
    actual = '✅ 적중' if y_f[idx] == 1 else '❌ 헛스윙'
    print(f"{rank:>4d} {str(d_f.iloc[idx].date()):<12s} {p_t5[idx]:>7.4f} {int(y_f[idx]):>9d} {actual}")

# Save (with type conversion)
def conv(obj):
    if isinstance(obj, dict): return {k: conv(v) for k, v in obj.items()}
    if isinstance(obj, list): return [conv(x) for x in obj]
    if isinstance(obj, (np.floating, np.float32, np.float64)): return float(obj)
    if isinstance(obj, (np.integer, np.int32, np.int64)): return int(obj)
    return obj

audit = {
    'cycle': '58DD_top_n_precision',
    'n_oos': int(n), 'n_real_bear': int(y_f.sum()), 'base_rate': float(base),
    'top_n_overall': conv(results_all),
    'top_n_per_period': conv(period_results),
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
