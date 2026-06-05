#!/usr/bin/env python3
"""360_stacking_meta_learner.py — Plan Phase 3 deep dive (P1 stacking meta)

설계:
  Stage 1: 3 base models (HGB + TimeMAE + Andreou) walk-forward predictions 재산출
  Stage 2: Regime features build (vol_z, ret_3m, drawdown_lvl, vol_diff_5y)
  Stage 3: Walk-forward online meta-learner
    - Meta input: [P_HGB, P_TimeMAE, P_Andreou, regime_features]
    - Meta model: Logistic L2 + HGB 둘 다 테스트
    - For each test month t, train meta on prior OOS predictions (months [t_start, t-1])
    - Predict month t
    - Minimum meta-train: 30 months

Compare:
  HGB baseline / TimeMAE / Andreou / T5 fixed ensemble / Meta-Logistic / Meta-HGB
Period-balanced + paired bootstrap.

Output: outputs/04_evaluation/cycle58dd_phase3_stacking_meta.json
"""
import json
import os
os.environ['CUBLAS_WORKSPACE_CONFIG'] = ':4096:8'
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"
OUT = EVAL / "cycle58dd_phase3_stacking_meta.json"
PRETRAIN_PATH = WS / "outputs/03_models/timemae_pretrain_v1.pt"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)

TEST_START = pd.Timestamp("2018-01-01")
SEQ_LEN = 21
META_MIN_TRAIN = 30


# === Load Andreou saved predictions ===
andreou_json = json.loads((EVAL / "cycle58dd_phase3_3_andreou.json").read_text())
andreou_preds = {pd.Timestamp(k): float(v) for k, v in andreou_json['predictions'].items()}
print(f"[Load Andreou] {len(andreou_preds)} predictions")

# === TimeMAE encoder ===
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


# === Load data ===
print(f"\n[Build] data pipeline")
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

# Regime features (already in monthly_features: ret_*, realized_vol_*, current_dd_pct, max_dd_*)
regime_cols = ['ret_1m', 'ret_3m', 'ret_6m', 'realized_vol_1m', 'realized_vol_3m',
               'realized_vol_12m', 'current_dd_pct', 'max_dd_6m', 'max_dd_12m']
regime_cols = [c for c in regime_cols if c in m.columns]
print(f"  regime cols ({len(regime_cols)}): {regime_cols}")

seqs = []; ys = []; dates = []; m_rows = []; regime_rows = []
for _, row in m.iterrows():
    ms = row['Date']; cut = ms - pd.Timedelta(days=1)
    cut_idx = (feat['Date'] <= cut).sum() - 1
    if cut_idx + 1 < SEQ_LEN: continue
    seq = feat_X[cut_idx - SEQ_LEN + 1 : cut_idx + 1]
    if seq.shape != (SEQ_LEN, len(feat_cols)): continue
    seqs.append(seq); ys.append(row['y_tail_q15']); dates.append(ms)
    m_rows.append(row[m_feat_cols].values)
    regime_rows.append(row[regime_cols].values)
X_seq = np.array(seqs, dtype=np.float32); y = np.array(ys, dtype=np.float32)
X_mon = np.array(m_rows, dtype=np.float32)
X_regime = np.array(regime_rows, dtype=np.float32)
dates = pd.to_datetime(dates)
test_idx = np.where(dates >= TEST_START)[0]
print(f"  total {len(X_seq)} sequences, OOS {len(test_idx)} months")

# === HGB monthly + TimeMAE annual ===
print("\n[Base 1: HGB monthly expanding]")
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

print("\n[Base 2: TimeMAE annual]")
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
            loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
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

# Align all 3
common_dates = pd.Series(d_hgb)
test_dates_arr = test_dates_s.values
tmae_align = np.full(len(common_dates), np.nan)
andr_align = np.full(len(common_dates), np.nan)
regime_align = np.full((len(common_dates), len(regime_cols)), np.nan)
for i, d in enumerate(common_dates):
    test_pos = np.where(test_dates_arr == d.to_numpy())[0]
    if len(test_pos) > 0:
        tmae_align[i] = p_tmae_all[test_pos[0]]
        regime_align[i] = X_regime[test_idx[test_pos[0]]]
    if d in andreou_preds:
        andr_align[i] = andreou_preds[d]

mask = ~np.isnan(tmae_align) & ~np.isnan(andr_align) & ~np.isnan(regime_align).any(axis=1)
p_hgb_f = p_hgb[mask]; p_tmae_f = tmae_align[mask]; p_andr_f = andr_align[mask]
y_f = y_hgb[mask]; d_f = pd.Series(d_hgb)[mask].reset_index(drop=True)
regime_f = regime_align[mask]
n = len(y_f); base = y_f.mean()
print(f"\n[Aligned] n={n}, base={base*100:.1f}%, regime_dim={regime_f.shape[1]}")

# === Stacking meta-learner walk-forward ===
print(f"\n[Stacking meta walk-forward, min_train={META_MIN_TRAIN}]")
# Build meta input: 3 base predictions + regime features
X_meta = np.column_stack([p_hgb_f, p_tmae_f, p_andr_f, regime_f])
print(f"  X_meta shape: {X_meta.shape}")

# Walk-forward: at each test month t (starting from min_train), train meta on [0, t-1], predict t
p_meta_lr = np.full(n, np.nan)
p_meta_hgb = np.full(n, np.nan)
for t in range(META_MIN_TRAIN, n):
    X_tr = X_meta[:t]; y_tr_meta = y_f[:t]
    if y_tr_meta.sum() < 5: continue
    # Logistic L2
    try:
        sc = StandardScaler()
        X_tr_sc = sc.fit_transform(X_tr); X_te_sc = sc.transform(X_meta[t:t+1])
        lr = LogisticRegression(C=0.5, penalty='l2', max_iter=2000, class_weight='balanced',
            solver='lbfgs', random_state=42)
        lr.fit(X_tr_sc, y_tr_meta)
        p_meta_lr[t] = lr.predict_proba(X_te_sc)[0, 1]
    except Exception:
        p_meta_lr[t] = (p_hgb_f[t] + p_tmae_f[t] + p_andr_f[t]) / 3  # fallback
    # HGB meta
    try:
        pw = (1 - y_tr_meta.mean()) / max(y_tr_meta.mean(), 1e-9)
        mh = HistGradientBoostingClassifier(max_iter=200, max_depth=3, learning_rate=0.05,
            class_weight='balanced', random_state=42)
        mh.fit(X_tr, y_tr_meta)
        p_meta_hgb[t] = mh.predict_proba(X_meta[t:t+1])[0, 1]
    except Exception:
        p_meta_hgb[t] = (p_hgb_f[t] + p_tmae_f[t] + p_andr_f[t]) / 3

# Filter: only months where meta predicted
meta_mask = ~np.isnan(p_meta_lr) & ~np.isnan(p_meta_hgb)
p_hgb_m = p_hgb_f[meta_mask]; p_tmae_m = p_tmae_f[meta_mask]; p_andr_m = p_andr_f[meta_mask]
p_meta_lr_m = p_meta_lr[meta_mask]; p_meta_hgb_m = p_meta_hgb[meta_mask]
y_m = y_f[meta_mask]; d_m = d_f[meta_mask].reset_index(drop=True)
n_m = len(y_m); base_m = y_m.mean()
print(f"  Meta OOS n={n_m}, base={base_m*100:.1f}%")

# T5 fixed ensemble (comparison reference)
p_t5 = 2/3 * p_hgb_m + 1/3 * np.maximum(p_tmae_m, p_andr_m)

# === Compare all ===
print(f"\n[Full meta OOS — all variants vs y_tail_q15]")
variants = {
    'HGB_only': p_hgb_m,
    'TimeMAE_only': p_tmae_m,
    'Andreou_only': p_andr_m,
    'T5_fixed (2/3 HGB + 1/3 max)': p_t5,
    'Meta_Logistic_L2': p_meta_lr_m,
    'Meta_HGB': p_meta_hgb_m,
}
results = {}
for name, p in variants.items():
    pr = average_precision_score(y_m, p)
    roc = roc_auc_score(y_m, p)
    results[name] = {'pr_auc': float(pr), 'lift': float(pr / base_m), 'roc': float(roc)}
    flag = '⭐' if pr > results.get('HGB_only', {'pr_auc': 0})['pr_auc'] else ''
    print(f"  {name:<35s} PR-AUC {pr:.4f} lift {pr/base_m:.2f}x ROC {roc:.4f} {flag}")

# Period-balanced
print(f"\n[Period-balanced]")
periods = [('2018-2020', '2018-01-01', '2020-12-31'),
           ('2021-2023', '2021-01-01', '2023-12-31'),
           ('2024-2026', '2024-01-01', '2026-12-31')]
print(f"{'Variant':<35s} {'2018-20':>10s} {'2021-23':>10s} {'2024-26':>10s}")
period_results = {}
for name, p in variants.items():
    row = {}
    for pname, s, e in periods:
        mask_p = ((d_m >= pd.Timestamp(s)) & (d_m <= pd.Timestamp(e))).values
        if mask_p.sum() < 8 or y_m[mask_p].sum() < 2:
            row[pname] = 'N/A'
        else:
            pr = average_precision_score(y_m[mask_p], p[mask_p])
            bp = y_m[mask_p].mean()
            row[pname] = f"{pr/bp:.2f}x"
    period_results[name] = row
    print(f"  {name:<35s} {row['2018-2020']:>10s} {row['2021-2023']:>10s} {row['2024-2026']:>10s}")

# Bootstrap CI paired (best meta vs HGB)
best_meta_k = max([k for k in results if 'Meta' in k], key=lambda k: results[k]['pr_auc'])
print(f"\n[Paired bootstrap CI 95% — {best_meta_k} vs HGB_only, B=5000]")
B = 5000; np.random.seed(42)
prs_h = []; prs_m_boot = []; deltas = []
for b in range(B):
    idx = np.random.choice(n_m, n_m, replace=True)
    if y_m[idx].sum() < 5: continue
    prs_h.append(average_precision_score(y_m[idx], p_hgb_m[idx]))
    prs_m_boot.append(average_precision_score(y_m[idx], variants[best_meta_k][idx]))
    deltas.append(prs_m_boot[-1] - prs_h[-1])
prs_h = np.array(prs_h); prs_m_boot = np.array(prs_m_boot); deltas = np.array(deltas)
print(f"  HGB CI:        [{np.quantile(prs_h, 0.025):.4f}, {np.quantile(prs_h, 0.975):.4f}]")
print(f"  {best_meta_k} CI: [{np.quantile(prs_m_boot, 0.025):.4f}, {np.quantile(prs_m_boot, 0.975):.4f}]")
print(f"  Delta CI:      [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
print(f"  P(meta > HGB) = {(deltas > 0).mean():.3f}")
print(f"  P(meta lift > 2x) = {(prs_m_boot > 2*base_m).mean():.3f}")
print(f"  P(HGB lift > 2x) = {(prs_h > 2*base_m).mean():.3f}")

# Also bootstrap T5 vs meta
p_t5_only = variants['T5_fixed (2/3 HGB + 1/3 max)']
print(f"\n[Paired bootstrap — {best_meta_k} vs T5_fixed, B=5000]")
np.random.seed(43)
prs_t5 = []; prs_m_boot2 = []; deltas_t5 = []
for b in range(B):
    idx = np.random.choice(n_m, n_m, replace=True)
    if y_m[idx].sum() < 5: continue
    prs_t5.append(average_precision_score(y_m[idx], p_t5_only[idx]))
    prs_m_boot2.append(average_precision_score(y_m[idx], variants[best_meta_k][idx]))
    deltas_t5.append(prs_m_boot2[-1] - prs_t5[-1])
prs_t5 = np.array(prs_t5); prs_m_boot2 = np.array(prs_m_boot2); deltas_t5 = np.array(deltas_t5)
print(f"  T5 CI:         [{np.quantile(prs_t5, 0.025):.4f}, {np.quantile(prs_t5, 0.975):.4f}]")
print(f"  Delta CI:      [{np.quantile(deltas_t5, 0.025):+.4f}, {np.quantile(deltas_t5, 0.975):+.4f}]")
print(f"  P(meta > T5)   = {(deltas_t5 > 0).mean():.3f}")

audit = {
    'cycle': '58DD_phase3_stacking_meta',
    'n_meta': int(n_m), 'base': float(base_m),
    'meta_min_train': META_MIN_TRAIN,
    'variants': results,
    'period_balanced': period_results,
    'best_meta': best_meta_k,
    'paired_bootstrap_meta_vs_hgb': {
        'hgb_ci': [float(np.quantile(prs_h, 0.025)), float(np.quantile(prs_h, 0.975))],
        'meta_ci': [float(np.quantile(prs_m_boot, 0.025)), float(np.quantile(prs_m_boot, 0.975))],
        'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
        'p_meta_gt_hgb': float((deltas > 0).mean()),
        'p_meta_lift_gt_2x': float((prs_m_boot > 2*base_m).mean()),
    },
    'paired_bootstrap_meta_vs_t5': {
        't5_ci': [float(np.quantile(prs_t5, 0.025)), float(np.quantile(prs_t5, 0.975))],
        'delta_ci': [float(np.quantile(deltas_t5, 0.025)), float(np.quantile(deltas_t5, 0.975))],
        'p_meta_gt_t5': float((deltas_t5 > 0).mean()),
    },
}
OUT.write_text(json.dumps(audit, indent=2))
print(f"\nSaved: {OUT}")
