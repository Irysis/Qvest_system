#!/usr/bin/env python3
"""352_precision_at_k.py — Production model의 '맞는 확률' 구체적 측정

도훈 mandate "모델이 맞는 확률은 몇이야" → precision-at-K 측정.

3 model + T5 ensemble의 다음 metrics:
  - Top 5%/10%/20%/30% picks precision (가장 강한 예측 시 정답률)
  - Best F1 threshold + precision/recall
  - Optimal threshold (Youden's J)
  - 도훈 친화 해석: "약세 매우 높음/가능성 있음" 분리

Output: outputs/04_evaluation/cycle58dd_precision_at_k.json
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
from sklearn.metrics import (
    precision_recall_curve, average_precision_score, roc_auc_score,
    confusion_matrix, f1_score)
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"
OUT = EVAL / "cycle58dd_precision_at_k.json"
PRETRAIN_DIR = WS / "outputs/03_models/timemae_pretrain_per_year"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)
TEST_START = pd.Timestamp("2018-01-01")
SEQ_LEN = 21
D_MODEL = 64; N_HEADS = 4; N_LAYERS = 2; DROPOUT = 0.10

# Andreou
andreou_json = json.loads((EVAL / "cycle58dd_phase3_3_andreou.json").read_text())
andreou_preds = {pd.Timestamp(k): float(v) for k, v in andreou_json['predictions'].items()}


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


# Load v5g + monthly
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
years = sorted(test_dates_s.dt.year.unique())
p_tmae_all = np.full(len(test_idx), np.nan)
for yr in years:
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

# Align
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
y_f = y_hgb[mask]; d_f = pd.Series(d_hgb)[mask].reset_index(drop=True)
n = len(y_f); base = y_f.mean()

# T5 ensemble
p_t5 = 2/3 * p_hgb_f + 1/3 * np.maximum(p_tmae_f, p_andr_f)

print(f"\n[Data] n={n} months, 실제 약세 {int(y_f.sum())}건 (base rate {base*100:.1f}%)")


def analyze(name, p, y):
    n = len(y); base = y.mean()
    # Top-K precision (가장 확신있는 K개 picks 중 실제 약세 비율)
    print(f"\n=== {name} ===")
    print(f"  평균 PR-AUC: {average_precision_score(y, p):.4f} (랜덤 baseline {base:.4f})")
    print(f"  ROC-AUC:     {roc_auc_score(y, p):.4f}")
    print(f"\n  '약세 매우 강함' 예측 (상위 K%) 중 실제 약세 비율 (precision):")
    print(f"  {'Top':>5s} {'K':>4s} {'TP':>4s} {'FP':>4s} {'Precision':>10s} {'vs Random':>10s}")
    pk_results = []
    for pct in [5, 10, 15, 20, 25, 30, 40, 50]:
        k = max(1, int(n * pct / 100))
        order = np.argsort(-p)
        topk = order[:k]
        tp = int(y[topk].sum())
        fp = k - tp
        prec = tp / k if k > 0 else 0
        lift = prec / base if base > 0 else 0
        print(f"  {pct:>4d}% {k:>4d} {tp:>4d} {fp:>4d} {prec:>9.1%} {lift:>9.2f}x")
        pk_results.append({'top_pct': pct, 'k': k, 'tp': tp, 'fp': fp,
                            'precision': prec, 'lift': lift})

    # Best F1 threshold
    pr_curve_p, pr_curve_r, thresholds = precision_recall_curve(y, p)
    # F1 = 2pr/(p+r)
    f1s = np.where((pr_curve_p + pr_curve_r) > 0,
                    2 * pr_curve_p * pr_curve_r / (pr_curve_p + pr_curve_r + 1e-9), 0)
    best_idx = np.argmax(f1s[:-1])  # exclude last point (recall=0)
    best_thr = thresholds[best_idx] if best_idx < len(thresholds) else thresholds[-1]
    best_prec = pr_curve_p[best_idx]; best_rec = pr_curve_r[best_idx]
    best_f1 = f1s[best_idx]
    n_pred_pos = (p >= best_thr).sum()
    print(f"\n  Best F1 threshold = {best_thr:.4f}:")
    print(f"    Precision: {best_prec:.1%} (예측 약세 {int(n_pred_pos)}건 중 {int(n_pred_pos*best_prec)}건 실제)")
    print(f"    Recall: {best_rec:.1%} (실제 약세 {int(y.sum())}건 중 잡아낸 비율)")
    print(f"    F1: {best_f1:.3f}")
    return {'pr_auc': float(average_precision_score(y, p)),
            'roc_auc': float(roc_auc_score(y, p)),
            'base_rate': float(base),
            'top_k_results': pk_results,
            'best_f1_threshold': float(best_thr),
            'best_f1_precision': float(best_prec),
            'best_f1_recall': float(best_rec),
            'best_f1': float(best_f1),
            'best_f1_n_predicted_positive': int(n_pred_pos)}


results = {}
for name, p in [('HGB_only', p_hgb_f), ('PerYear_TimeMAE', p_tmae_f),
                ('Andreou_only', p_andr_f), ('T5_per_year (production)', p_t5)]:
    results[name] = analyze(name, p, y_f)

OUT.write_text(json.dumps(results, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
