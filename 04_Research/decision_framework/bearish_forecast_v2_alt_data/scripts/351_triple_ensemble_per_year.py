#!/usr/bin/env python3
"""351_triple_ensemble_per_year.py — Per-year TimeMAE 적용 후 triple ensemble 재계산

323 결과: per-year pretrain이 모든 period 개선 (2018-20 +0.25x, 2021-23 +0.10x, 2024-26 +0.39x).
지금 triple ensemble 재구성:
  HGB V1 monthly expanding (단독 lift 1.72x aligned)
  + per-year TimeMAE (lift 1.37x, periods 1.17/1.32/4.57x)
  + Andreou options (lift 1.25x, periods 1.81/1.17/2.35x)

Saved per-year encoders: outputs/03_models/timemae_pretrain_per_year/timemae_pretrain_v2_{yr}.pt
재학습 없이 encoder load → fine-tune → ensemble.

Output: outputs/04_evaluation/cycle58dd_phase3_triple_per_year.json
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
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"
OUT = EVAL / "cycle58dd_phase3_triple_per_year.json"
PRETRAIN_DIR = WS / "outputs/03_models/timemae_pretrain_per_year"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)

TEST_START = pd.Timestamp("2018-01-01")
SEQ_LEN = 21
D_MODEL = 64; N_HEADS = 4; N_LAYERS = 2; DROPOUT = 0.10

# Load Andreou
andreou_json = json.loads((EVAL / "cycle58dd_phase3_3_andreou.json").read_text())
andreou_preds = {pd.Timestamp(k): float(v) for k, v in andreou_json['predictions'].items()}
print(f"[Load Andreou] {len(andreou_preds)} predictions")


class TimeMAEEncoder(nn.Module):
    def __init__(self, n_features, d_model=D_MODEL, n_heads=N_HEADS, n_layers=N_LAYERS,
                 dropout=DROPOUT, seq_len=SEQ_LEN):
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


# Load v5g daily features (raw — per-year mu/sd applied)
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
print(f"[Data] {len(X_seq_raw)} sequences, OOS {len(test_idx)} months")


# === HGB monthly expanding ===
print("\n[HGB V1 monthly expanding]")
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

# === Per-year TimeMAE: load saved encoder, fine-tune, predict ===
print("\n[Per-year TimeMAE — load saved encoders, fine-tune, predict]")
def fine_tune(encoder_state, n_features, X_tr, y_tr, epochs=30, lr=5e-4):
    enc = TimeMAEEncoder(n_features=n_features).to(DEVICE)
    enc.load_state_dict(encoder_state, strict=True)
    model = BearClassifier(enc, d_model=D_MODEL).to(DEVICE)
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
    # Load saved encoder for this year
    enc_path = PRETRAIN_DIR / f"timemae_pretrain_v2_{yr}.pt"
    if not enc_path.exists():
        print(f"  Year {yr}: encoder file MISSING {enc_path.name}")
        continue
    ckpt = torch.load(enc_path, map_location=DEVICE, weights_only=False)
    mu_y = np.array(ckpt['mu']); sd_y = np.array(ckpt['sd'])
    # Standardize X_seq with year-specific mu/sd
    X_seq_std = ((X_seq_raw - mu_y) / sd_y).astype(np.float32)
    # Fine-tune
    model = fine_tune(ckpt['state_dict'], len(feat_cols), X_seq_std[tr_idx], y[tr_idx])
    p_tmae_all[yr_pos] = predict_t(model, X_seq_std[test_idx[yr_pos]])
    print(f"  Year {yr}: predicted {int(yr_mask.sum())} months")

# Align all 3
common_dates = pd.Series(d_hgb)
test_dates_arr = test_dates_s.values
tmae_align = np.full(len(common_dates), np.nan)
andr_align = np.full(len(common_dates), np.nan)
for i, d in enumerate(common_dates):
    test_pos = np.where(test_dates_arr == d.to_numpy())[0]
    if len(test_pos) > 0:
        tmae_align[i] = p_tmae_all[test_pos[0]]
    if d in andreou_preds:
        andr_align[i] = andreou_preds[d]

mask = ~np.isnan(tmae_align) & ~np.isnan(andr_align)
p_hgb_f = p_hgb[mask]; p_tmae_f = tmae_align[mask]; p_andr_f = andr_align[mask]
y_f = y_hgb[mask]; d_f = pd.Series(d_hgb)[mask].reset_index(drop=True)
n = len(y_f); base = y_f.mean()
print(f"\n[Aligned] n={n}, base={base*100:.1f}%")

# Individual
results = {}
print(f"\n[Individual models]")
for name, p in [('HGB', p_hgb_f), ('PerYear_TimeMAE', p_tmae_f), ('Andreou_opt', p_andr_f)]:
    pr = average_precision_score(y_f, p); roc = roc_auc_score(y_f, p)
    results[name] = {'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc)}
    print(f"  {name:<20s} PR-AUC {pr:.4f} lift {pr/base:.2f}x ROC {roc:.4f}")

# Correlations
print(f"\n  cor(HGB, PerYearTimeMAE) = {np.corrcoef(p_hgb_f, p_tmae_f)[0, 1]:+.3f}")
print(f"  cor(HGB, Andreou)        = {np.corrcoef(p_hgb_f, p_andr_f)[0, 1]:+.3f}")
print(f"  cor(PerYearTmae, Andreou)= {np.corrcoef(p_tmae_f, p_andr_f)[0, 1]:+.3f}")

# Triple ensemble
print("\n[Triple ensemble — Per-year TimeMAE]")
ens = {
    'HGB_only': p_hgb_f,
    'PerYearTimeMAE_only': p_tmae_f,
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
        mask_p = ((d_f >= pd.Timestamp(s)) & (d_f <= pd.Timestamp(e))).values
        if mask_p.sum() < 12 or y_f[mask_p].sum() < 2:
            row[pname] = 'N/A'
        else:
            pr = average_precision_score(y_f[mask_p], p[mask_p])
            bp = y_f[mask_p].mean()
            row[pname] = f"{pr/bp:.2f}x"
    period_results[name] = row
    print(f"  {name:<28s} {row['2018-2020']:>10s} {row['2021-2023']:>10s} {row['2024-2026']:>10s}")

# Best ensemble paired bootstrap
ens_only = {k: v for k, v in results.items() if k.startswith('T')}
best_k = max(ens_only.keys(), key=lambda k: ens_only[k]['pr_auc'])
print(f"\n[Paired bootstrap — {best_k} vs HGB, B=5000]")
B = 5000; np.random.seed(42)
prs_h = []; prs_b = []; deltas = []
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_f[idx].sum() < 5: continue
    prs_h.append(average_precision_score(y_f[idx], p_hgb_f[idx]))
    prs_b.append(average_precision_score(y_f[idx], ens[best_k][idx]))
    deltas.append(prs_b[-1] - prs_h[-1])
prs_h = np.array(prs_h); prs_b = np.array(prs_b); deltas = np.array(deltas)
print(f"  HGB CI:        [{np.quantile(prs_h, 0.025):.4f}, {np.quantile(prs_h, 0.975):.4f}]")
print(f"  {best_k} CI:  [{np.quantile(prs_b, 0.025):.4f}, {np.quantile(prs_b, 0.975):.4f}]")
print(f"  Delta CI:      [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
print(f"  P(best > HGB) = {(deltas > 0).mean():.3f}")
print(f"  P(best lift > 2x) = {(prs_b > 2*base).mean():.3f}")
print(f"  P(HGB lift > 2x) = {(prs_h > 2*base).mean():.3f}")

audit = {
    'cycle': '58DD_phase3_triple_per_year',
    'n': int(n), 'base': float(base),
    'individual': results,
    'period_balanced': period_results,
    'correlations': {
        'hgb_perYearTmae': float(np.corrcoef(p_hgb_f, p_tmae_f)[0, 1]),
        'hgb_andreou': float(np.corrcoef(p_hgb_f, p_andr_f)[0, 1]),
        'perYearTmae_andreou': float(np.corrcoef(p_tmae_f, p_andr_f)[0, 1]),
    },
    'best_ensemble': best_k,
    'paired_bootstrap_best_vs_hgb': {
        'hgb_ci': [float(np.quantile(prs_h, 0.025)), float(np.quantile(prs_h, 0.975))],
        'best_ci': [float(np.quantile(prs_b, 0.025)), float(np.quantile(prs_b, 0.975))],
        'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
        'p_best_gt_hgb': float((deltas > 0).mean()),
        'p_best_lift_gt_2x': float((prs_b > 2*base).mean()),
    },
}
OUT.write_text(json.dumps(audit, indent=2))
print(f"\nSaved: {OUT}")
