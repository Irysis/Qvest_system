#!/usr/bin/env python3
"""322_hgb_timemae_ensemble.py — HGB × TimeMAE complementary ensemble

발견 (321):
  HGB V1 expanding:  2018-2020 1.93x / 2021-2023 2.41x / 2024-2026 1.17x  Full 2.00x
  TimeMAE annual:    2018-2020 0.92x / 2021-2023 1.22x / 2024-2026 4.18x  Full 1.38x
  → period-strength 완벽 complementary

Ensemble variants:
  E1: mean(P_hgb, P_tmae)
  E2: max(P_hgb, P_tmae)
  E3: regime-aware = 2/3*P_hgb + 1/3*P_tmae (HGB heavy)
  E4: 1/3*P_hgb + 2/3*P_tmae (TimeMAE heavy)
  E5: dynamic regime weights — based on rolling realized vol (high vol → TimeMAE weight up)

Output: outputs/04_evaluation/cycle58dd_phase3_1_ensemble.json
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
PRETRAIN_PATH = WS / "outputs/03_models/timemae_pretrain_v1.pt"
OUT_E = WS / "outputs/04_evaluation/cycle58dd_phase3_1_ensemble.json"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)

TEST_START = pd.Timestamp("2018-01-01")
SEQ_LEN = 21
FT_EPOCHS = 30
FT_LR = 5e-4
FT_BATCH = 64

# Load pretrained encoder
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
        h = self.encoder.encode(x); h = h.mean(dim=1)
        h = self.dropout(h)
        return self.head(h).squeeze(-1)


# Build month-start sequences (daily v5g) AND monthly features (V1)
def load_dual_data():
    feat = pd.read_parquet(DATA / "feature_panel_v5g_cross_market.parquet")
    feat['Date'] = pd.to_datetime(feat['Date']); feat = feat.sort_values('Date').reset_index(drop=True)
    feat[feat_cols] = feat[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    feat[feat_cols] = (feat[feat_cols] - mu) / sd  # use SAME normalization as pretrain
    feat_X = feat[feat_cols].values

    m = pd.read_parquet(DATA / "monthly_features.parquet")
    m['Date'] = pd.to_datetime(m['Date'])
    m = m.dropna(subset=['y_tail_q15']).reset_index(drop=True)
    m_feat_cols = [c for c in m.columns if c not in ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']]
    m[m_feat_cols] = m[m_feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)

    seqs = []; ys = []; dates = []; m_rows = []
    for _, row in m.iterrows():
        ms = row['Date']
        cut = ms - pd.Timedelta(days=1)
        cut_idx = (feat['Date'] <= cut).sum() - 1
        if cut_idx + 1 < SEQ_LEN: continue
        seq = feat_X[cut_idx - SEQ_LEN + 1: cut_idx + 1]
        if seq.shape != (SEQ_LEN, len(feat_cols)): continue
        seqs.append(seq); ys.append(row['y_tail_q15']); dates.append(ms)
        m_rows.append(row[m_feat_cols].values)
    X_seq = np.array(seqs, dtype=np.float32)
    y = np.array(ys, dtype=np.float32)
    X_mon = np.array(m_rows, dtype=np.float32)
    dates = pd.to_datetime(dates)
    print(f"[Data] {len(X_seq)} months, seq={X_seq.shape}, mon={X_mon.shape}, base={y.mean()*100:.1f}%")
    return X_seq, X_mon, y, dates, m_feat_cols


def fine_tune_timemae(X_tr, y_tr, epochs=FT_EPOCHS, lr=FT_LR, batch=FT_BATCH):
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
    loader = DataLoader(TensorDataset(Xt, yt), batch_size=batch, shuffle=True, drop_last=False)
    for _ in range(epochs):
        model.train()
        for xb, yb in loader:
            opt.zero_grad()
            logits = model(xb); loss = loss_fn(logits, yb)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
        sched.step()
    return model


def predict_timemae(model, X):
    model.eval()
    with torch.no_grad():
        Xt = torch.from_numpy(X).to(DEVICE)
        return torch.sigmoid(model(Xt)).cpu().numpy()


def main():
    X_seq, X_mon, y, dates, m_fc = load_dual_data()
    test_mask = dates >= TEST_START
    test_idx = np.where(test_mask)[0]
    print(f"\n[OOS] {len(test_idx)} months")

    # === HGB V1 expanding monthly (replicate baseline) ===
    print("\n[HGB V1 expanding monthly]")
    p_hgb = []; y_hgb = []; dates_hgb = []
    for i in test_idx:
        tr = np.arange(0, i)
        if y[tr].sum() < 20: continue
        m = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
            class_weight='balanced', random_state=42)
        m.fit(X_mon[tr], y[tr])
        p_hgb.append(m.predict_proba(X_mon[i:i+1])[0, 1])
        y_hgb.append(y[i]); dates_hgb.append(dates[i])
    p_hgb = np.array(p_hgb); y_hgb = np.array(y_hgb); dates_hgb = pd.to_datetime(dates_hgb)
    base = y_hgb.mean(); n = len(y_hgb)
    pr_hgb = average_precision_score(y_hgb, p_hgb)
    print(f"  PR-AUC {pr_hgb:.4f} lift {pr_hgb/base:.2f}x  (n={n}, base {base*100:.1f}%)")

    # === TimeMAE annual retrain ===
    print("\n[TimeMAE annual retrain]")
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
        model = fine_tune_timemae(X_seq[tr_idx], y[tr_idx])
        p_tmae_all[yr_pos] = predict_timemae(model, X_seq[test_idx[yr_pos]])
        print(f"  Year {yr}: trained on {len(tr_idx)} months, predicted {int(yr_mask.sum())} months")

    # Align with HGB (filter to common predictions, since HGB skipped early months with insufficient positives)
    test_dates_arr = test_dates_s.values
    # Find indices in test where HGB made predictions
    common_dates = pd.Series(dates_hgb)
    align_idx = np.array([np.where(test_dates_arr == d)[0][0] for d in common_dates])
    p_tmae = p_tmae_all[align_idx]
    valid_tmae = ~np.isnan(p_tmae)
    # Apply both filters
    final_mask = valid_tmae
    if final_mask.sum() < len(p_hgb):
        # Some TimeMAE skipped → drop those from analysis
        p_hgb_f = p_hgb[final_mask]; p_tmae_f = p_tmae[final_mask]
        y_f = y_hgb[final_mask]; dates_f = dates_hgb[final_mask]
    else:
        p_hgb_f = p_hgb; p_tmae_f = p_tmae; y_f = y_hgb; dates_f = dates_hgb
    n_f = len(y_f); base_f = y_f.mean()
    print(f"\n[Aligned] n={n_f}, base={base_f*100:.1f}%")
    pr_tmae = average_precision_score(y_f, p_tmae_f)
    print(f"  TimeMAE PR-AUC: {pr_tmae:.4f} lift {pr_tmae/base_f:.2f}x")
    print(f"  HGB    PR-AUC: {average_precision_score(y_f, p_hgb_f):.4f} lift {average_precision_score(y_f, p_hgb_f)/base_f:.2f}x")
    print(f"  cor(P_hgb, P_tmae): {np.corrcoef(p_hgb_f, p_tmae_f)[0, 1]:.3f}")

    # Ensemble variants
    print("\n[Ensemble variants — vs y_tail_q15]")
    ens = {
        'P_hgb_only': p_hgb_f,
        'P_tmae_only': p_tmae_f,
        'E1_mean': (p_hgb_f + p_tmae_f) / 2,
        'E2_max': np.maximum(p_hgb_f, p_tmae_f),
        'E3_hgb_2/3': 2/3 * p_hgb_f + 1/3 * p_tmae_f,
        'E4_tmae_2/3': 1/3 * p_hgb_f + 2/3 * p_tmae_f,
    }
    results = {}
    for name, p in ens.items():
        pr = average_precision_score(y_f, p); roc = roc_auc_score(y_f, p)
        results[name] = {'pr_auc': float(pr), 'lift': float(pr / base_f), 'roc': float(roc)}
        flag = '⭐' if pr > pr_hgb else ''
        print(f"  {name:<18s} PR-AUC {pr:.4f} lift {pr/base_f:.2f}x ROC {roc:.4f} {flag}")

    # Period-balanced
    print("\n[Period-balanced — best ensemble + HGB + TimeMAE alone]")
    periods = [('2018-2020', '2018-01-01', '2020-12-31'),
               ('2021-2023', '2021-01-01', '2023-12-31'),
               ('2024-2026', '2024-01-01', '2026-12-31')]
    print(f"{'Variant':<18s} {'2018-20':>10s} {'2021-23':>10s} {'2024-26':>10s}")
    period_results = {}
    dates_f_s = pd.Series(dates_f)
    for name, p in ens.items():
        row = {}
        for pname, s, e in periods:
            mask = ((dates_f_s >= pd.Timestamp(s)) & (dates_f_s <= pd.Timestamp(e))).values
            if mask.sum() < 12 or y_f[mask].sum() < 2:
                row[pname] = 'N/A'
            else:
                pr = average_precision_score(y_f[mask], p[mask])
                bp = y_f[mask].mean()
                row[pname] = f"{pr/bp:.2f}x"
        period_results[name] = row
        print(f"  {name:<18s} {row['2018-2020']:>10s} {row['2021-2023']:>10s} {row['2024-2026']:>10s}")

    # Bootstrap paired — best ensemble vs HGB baseline
    ens_only = {k: v for k, v in results.items() if k.startswith('E')}
    best_k = max(ens_only.keys(), key=lambda k: ens_only[k]['pr_auc'])
    print(f"\n[Paired bootstrap — {best_k} vs P_hgb_only, B=5000]")
    B = 5000; np.random.seed(42)
    prs_base = []; prs_best = []; deltas = []
    p_bb = ens[best_k]
    for b in range(B):
        idx = np.random.choice(n_f, n_f, replace=True)
        if y_f[idx].sum() < 5: continue
        prs_base.append(average_precision_score(y_f[idx], p_hgb_f[idx]))
        prs_best.append(average_precision_score(y_f[idx], p_bb[idx]))
        deltas.append(prs_best[-1] - prs_base[-1])
    prs_base = np.array(prs_base); prs_best = np.array(prs_best); deltas = np.array(deltas)
    print(f"  HGB CI:        [{np.quantile(prs_base, 0.025):.4f}, {np.quantile(prs_base, 0.975):.4f}]")
    print(f"  {best_k} CI: [{np.quantile(prs_best, 0.025):.4f}, {np.quantile(prs_best, 0.975):.4f}]")
    print(f"  Delta CI:      [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
    print(f"  P(ensemble > HGB) = {(deltas > 0).mean():.3f}")
    print(f"  P(ensemble lift > 2x) = {(prs_best > 2*base_f).mean():.3f}")
    print(f"  P(HGB lift > 2x) = {(prs_base > 2*base_f).mean():.3f}")

    audit = {
        'cycle': '58DD_phase3_1_hgb_timemae_ensemble',
        'n': int(n_f),
        'base': float(base_f),
        'hgb_pr_auc': float(pr_hgb),
        'tmae_pr_auc': float(pr_tmae),
        'pred_correlation': float(np.corrcoef(p_hgb_f, p_tmae_f)[0, 1]),
        'ensemble_results': results,
        'period_balanced': period_results,
        'best_ensemble': best_k,
        'paired_bootstrap_best_vs_hgb': {
            'hgb_ci': [float(np.quantile(prs_base, 0.025)), float(np.quantile(prs_base, 0.975))],
            'best_ci': [float(np.quantile(prs_best, 0.025)), float(np.quantile(prs_best, 0.975))],
            'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
            'p_best_gt_hgb': float((deltas > 0).mean()),
            'p_best_lift_gt_2x': float((prs_best > 2*base_f).mean()),
        }
    }
    OUT_E.write_text(json.dumps(audit, indent=2))
    print(f"\nSaved: {OUT_E}")


if __name__ == '__main__':
    main()
